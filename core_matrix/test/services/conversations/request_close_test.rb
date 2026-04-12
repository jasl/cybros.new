require "test_helper"

class Conversations::RequestCloseTest < ActiveSupport::TestCase
  test "archive intent rejects conversations that are not retained" do
    conversation = create_conversation!
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "archive"
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before archival"
  end

  test "delete intent preserves lifecycle state while marking the conversation pending delete" do
    conversation = create_conversation!
    conversation.update!(lifecycle_state: "archived")

    closed = Conversations::RequestClose.call(
      conversation: conversation,
      intent_kind: "delete",
      occurred_at: Time.zone.parse("2026-03-29 08:00:00 UTC")
    )

    close_operation = closed.reload.conversation_close_operations.order(:created_at).last

    assert closed.pending_delete?
    assert closed.archived?
    assert_equal "delete", close_operation.intent_kind
    assert_equal Time.zone.parse("2026-03-29 08:00:00 UTC"), close_operation.requested_at
    assert_equal Time.zone.parse("2026-03-29 08:00:00 UTC"), closed.deleted_at
  end

  test "rejects switching intent while a close operation is unfinished" do
    conversation = create_conversation!
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "delete"
      )
    end

    assert_includes error.record.errors[:intent_kind], "must not change while a close operation is unfinished"
  end

  test "reuses the existing close operation when the same intent is retried" do
    conversation = create_conversation!
    occurred_at = Time.zone.parse("2026-03-29 08:00:00 UTC")

    first = Conversations::RequestClose.call(
      conversation: conversation,
      intent_kind: "delete",
      occurred_at: occurred_at
    )
    second = Conversations::RequestClose.call(
      conversation: conversation.reload,
      intent_kind: "delete",
      occurred_at: occurred_at + 5.minutes
    )

    close_operation = second.reload.conversation_close_operations.order(:created_at).last

    assert_equal first.deleted_at, second.deleted_at
    assert_equal 1, second.conversation_close_operations.count
    assert_equal "delete", close_operation.intent_kind
    assert_equal occurred_at, close_operation.requested_at
  end

  test "keeps nested owned subagent close orchestration under query budget" do
    context = create_workspace_context!
    conversation = create_root_conversation!(context: context)
    first_session = create_owned_subagent_connection!(
      context: context,
      owner_conversation: conversation
    )
    second_session = create_owned_subagent_connection!(
      context: context,
      owner_conversation: first_session.conversation
    )
    create_owned_subagent_connection!(
      context: context,
      owner_conversation: second_session.conversation
    )

    queries = capture_sql_queries do
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "delete",
        occurred_at: Time.zone.parse("2026-03-29 08:00:00 UTC")
      )
    end

    assert_operator queries.length, :<=, 70, "Expected request close to stay under 70 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end

  test "records completion on a linked conversation control request" do
    conversation = create_conversation!
    session = ConversationSupervisionSession.create!(
      installation: conversation.installation,
      target_conversation: conversation,
      initiator: conversation.workspace.user,
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: conversation.installation,
      conversation_supervision_session: session,
      target_conversation: conversation,
      request_kind: "request_conversation_close",
      target_kind: "conversation",
      target_public_id: conversation.public_id,
      lifecycle_state: "queued",
      request_payload: { "intent_kind" => "archive" },
      result_payload: {}
    )

    Conversations::RequestClose.call(
      conversation: conversation,
      intent_kind: "archive",
      occurred_at: Time.zone.parse("2026-03-29 08:05:00 UTC"),
      conversation_control_request: control_request
    )

    assert_equal "completed", control_request.reload.lifecycle_state
    assert_equal conversation.public_id, control_request.result_payload["conversation_id"]
  end

  private

  def create_conversation!
    context = create_workspace_context!
    create_root_conversation!(context: context)
  end

  def create_root_conversation!(context:)
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
  end

  def create_owned_subagent_connection!(context:, owner_conversation:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      addressability: "agent_addressable"
    )

    SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
  end
end
