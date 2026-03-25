require "test_helper"

class Conversations::RequestDeletionTest < ActiveSupport::TestCase
  test "marks the conversation pending delete, cancels queued and waiting work, and revokes publications" do
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
    assert_equal "conversation_deleted", context[:turn].cancellation_reason_kind

    workflow_run = context[:workflow_run].reload
    assert workflow_run.canceled?
    assert workflow_run.ready?
    assert_equal "conversation_deleted", workflow_run.cancellation_reason_kind
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id

    assert request.reload.canceled?
    assert_equal "canceled", request.resolution_kind
    assert_equal "conversation_deleted", request.result_payload["reason"]

    assert publication.reload.disabled?
    assert publication.revoked?
  end

  test "stops running processes, cancels subagents, and releases their active leases" do
    context = build_subagent_context!
    process_node = create_workflow_node!(
      workflow_run: context[:workflow_run],
      node_key: "process",
      node_type: "turn_command",
      decision_source: "agent_program",
      metadata: {}
    )
    process_run = Processes::Start.call(
      workflow_node: process_node,
      execution_environment: context[:execution_environment],
      kind: "turn_command",
      command_line: "echo hi",
      timeout_seconds: 30,
      origin_message: context[:turn].selected_input_message
    )
    subagent_run = Subagents::Spawn.call(
      workflow_node: context[:workflow_node],
      requested_role_or_slot: "researcher"
    )
    process_lease = Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: "runtime-process",
      heartbeat_timeout_seconds: 30
    )
    subagent_lease = Leases::Acquire.call(
      leased_resource: subagent_run,
      holder_key: "runtime-subagent",
      heartbeat_timeout_seconds: 30
    )

    Conversations::RequestDeletion.call(conversation: context[:conversation], occurred_at: Time.current)

    assert process_run.reload.stopped?
    assert_equal "conversation_deleted", process_run.metadata["stop_reason"]
    assert subagent_run.reload.canceled?
    assert_not_nil subagent_run.finished_at

    assert_not process_lease.reload.active?
    assert_equal "conversation_deleted", process_lease.release_reason
    assert_not subagent_lease.reload.active?
    assert_equal "conversation_deleted", subagent_lease.release_reason

    assert context[:workflow_run].reload.canceled?
    assert context[:turn].reload.canceled?
  end

  test "is idempotent and preserves the original deleted_at timestamp" do
    conversation = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
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
end
