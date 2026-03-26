require "test_helper"

class Conversations::FinalizeDeletionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "marks a pending deletion deleted, removes the canonical store reference, and enqueues gc" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    Conversations::RequestDeletion.call(conversation: conversation)

    assert_enqueued_with(job: CanonicalStores::GarbageCollectJob) do
      finalized = Conversations::FinalizeDeletion.call(conversation: conversation.reload)
      close_operation = finalized.reload.conversation_close_operations.order(:created_at).last

      assert finalized.deleted?
      assert_nil finalized.canonical_store_reference
      assert_not_nil finalized.deleted_at
      assert_equal "completed", close_operation.lifecycle_state
      assert_not_nil close_operation.completed_at
      assert_equal 0, close_operation.summary_payload.dig("tail", "running_background_process_count")
    end
  end

  test "allows finalization once the mainline barrier is clear even if tail cleanup is still disposing" do
    context = build_agent_control_context!
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    Conversations::RequestDeletion.call(conversation: context[:conversation], occurred_at: Time.current)
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
    background_service.update!(
      close_state: "requested",
      close_reason_kind: "conversation_deleted",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now
    )

    assert_enqueued_with(job: CanonicalStores::GarbageCollectJob) do
      finalized = Conversations::FinalizeDeletion.call(conversation: context[:conversation].reload)
      close_operation = finalized.reload.conversation_close_operations.order(:created_at).last

      assert finalized.deleted?
      assert_equal "requested", background_service.reload.close_state
      assert_equal "disposing", close_operation.lifecycle_state
      assert_nil close_operation.completed_at
      assert_equal 1, close_operation.summary_payload.dig("tail", "running_background_process_count")
    end
  end

  test "rejects finalization while the mainline barrier still has an active turn" do
    context = build_canonical_variable_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::FinalizeDeletion.call(conversation: context[:conversation])
    end

    assert_includes error.record.errors[:base], "must not have active turns before final deletion"
  end
end
