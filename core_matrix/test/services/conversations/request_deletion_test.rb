require "test_helper"

class Conversations::RequestDeletionTest < ActiveSupport::TestCase
  test "preserves archived lifecycle state while moving to pending delete" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(lifecycle_state: "archived")

    deleted = Conversations::RequestDeletion.call(conversation: conversation, occurred_at: Time.current)

    assert deleted.pending_delete?
    assert deleted.archived?
  end

  test "marks the conversation pending delete immediately, fences the active turn, and revokes publications" do
    context = build_human_interaction_context!
    queued_turn = Turns::QueueFollowUp.call(
      conversation: context[:conversation],
      content: "Queued follow up",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )
    publication = Publications::PublishLive.call(
      conversation: context[:conversation],
      actor: context[:user],
      visibility_mode: "external_public"
    )

    deleted = Conversations::RequestDeletion.call(conversation: context[:conversation], occurred_at: Time.current)

    assert deleted.pending_delete?
    assert_not_nil deleted.deleted_at
    assert queued_turn.reload.canceled?
    assert_equal "conversation_deleted", queued_turn.cancellation_reason_kind
    assert context[:turn].reload.canceled?
    assert_equal "turn_interrupted", context[:turn].cancellation_reason_kind

    workflow_run = context[:workflow_run].reload
    assert workflow_run.canceled?
    assert_equal "turn_interrupted", workflow_run.cancellation_reason_kind

    assert request.reload.canceled?
    assert_equal "canceled", request.resolution_kind
    assert_equal "turn_interrupted", request.result_payload["reason"]

    assert publication.reload.disabled?
    assert publication.revoked?

    close_operation = deleted.reload.conversation_close_operations.order(:created_at).last
    assert_equal "delete", close_operation.intent_kind
    assert_equal "quiescing", close_operation.lifecycle_state
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_turn_count")
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_workflow_count")
    assert_equal 0, close_operation.summary_payload.dig("mainline", "open_blocking_interaction_count")
  end

  test "delete close also targets detached background processes without stopping them synchronously" do
    context = build_agent_control_context!
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: background_service,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    Conversations::RequestDeletion.call(conversation: context[:conversation], occurred_at: Time.current)

    background_service.reload
    assert_equal "requested", background_service.close_state
    assert background_service.running?

    close_request = AgentControlMailboxItem.where(item_type: "resource_close_request").order(:created_at).last
    assert_equal "deletion_force_quiesce", close_request.payload["request_kind"]
    assert_equal background_service.public_id, close_request.payload["resource_id"]
  end

  test "is idempotent and preserves the original deleted_at timestamp" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    original_deleted_at = Time.zone.parse("2026-03-25 09:00:00 UTC")

    first_deleted = Conversations::RequestDeletion.call(conversation: conversation, occurred_at: original_deleted_at)
    second_deleted = Conversations::RequestDeletion.call(
      conversation: conversation.reload,
      occurred_at: original_deleted_at + 5.minutes
    )

    assert_equal first_deleted.deleted_at, second_deleted.deleted_at
    assert_equal original_deleted_at, second_deleted.deleted_at
    assert second_deleted.pending_delete?
  end

  test "reloads a cached nil publication association before revoking during deletion" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    stale_conversation = Conversation.find(conversation.id)
    assert_nil stale_conversation.publication

    publication = Publications::PublishLive.call(
      conversation: conversation,
      actor: context[:user],
      visibility_mode: "external_public"
    )

    Conversations::RequestDeletion.call(conversation: stale_conversation, occurred_at: Time.current)

    assert publication.reload.disabled?
    assert publication.revoked?
  end

  test "preserves original deleted_at when deletion is retried from a stale conversation shell" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    stale_conversation = Conversation.find(conversation.id)
    original_deleted_at = Time.zone.parse("2026-03-25 09:00:00 UTC")

    first_deleted = Conversations::RequestDeletion.call(conversation: conversation, occurred_at: original_deleted_at)
    second_deleted = Conversations::RequestDeletion.call(
      conversation: stale_conversation,
      occurred_at: original_deleted_at + 5.minutes
    )

    assert_equal original_deleted_at, first_deleted.deleted_at
    assert_equal first_deleted.deleted_at, second_deleted.deleted_at
    assert_equal 1, conversation.reload.conversation_close_operations.count
  end
end
