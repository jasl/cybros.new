require "test_helper"

class Conversations::ValidateQuiescenceTest < ActiveSupport::TestCase
  test "archival rejects open owned subagent connections" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    session = create_owned_subagent_connection!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: "archival",
        mainline_only: false
      )
    end

    assert_equal conversation.id, error.record.id
    assert_includes error.record.errors[:base], "must not have open subagent connections before archival"
    assert session.reload.close_open?
  end

  test "purge rejects close-pending owned subagent connections" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    session = create_owned_subagent_connection!(
      installation: context[:installation],
      workspace: context[:workspace],
      owner_conversation: conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    session.update!(
      close_state: "requested",
      close_reason_kind: "conversation_deleted",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: "purge",
        mainline_only: false
      )
    end

    assert_equal conversation.id, error.record.id
    assert_includes error.record.errors[:base], "must not have open or close-pending subagent connections before purge"
    assert_equal "close_requested", session.reload.derived_close_status
  end

  test "final deletion ignores disposing background-service tails once the mainline barrier is clear" do
    context = build_agent_control_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)
    context[:turn].update!(
      lifecycle_state: "canceled",
      cancellation_requested_at: Time.current,
      cancellation_reason_kind: "turn_interrupted"
    )
    context[:workflow_run].update!(
      lifecycle_state: "canceled",
      wait_state: "ready",
      wait_reason_kind: nil,
      wait_reason_payload: {},
      waiting_since_at: nil,
      blocking_resource_type: nil,
      blocking_resource_id: nil,
      cancellation_requested_at: Time.current,
      cancellation_reason_kind: "turn_interrupted"
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    background_service.update!(
      close_state: "requested",
      close_reason_kind: "conversation_deleted",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now
    )

    validated = Conversations::ValidateQuiescence.call(
      conversation: context[:conversation],
      stage: "final deletion",
      mainline_only: true
    )

    assert_equal context[:conversation].id, validated.id
  end

  private

  def create_owned_subagent_connection!(installation:, workspace:, owner_conversation:, execution_runtime:, agent_definition_version:)
    child_conversation = create_conversation_record!(
      installation: installation,
      workspace: workspace,
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: execution_runtime,
      agent_definition_version: agent_definition_version,
      addressability: "agent_addressable"
    )
    SubagentConnection.create!(
      installation: installation,
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "idle"
    )
  end
end
