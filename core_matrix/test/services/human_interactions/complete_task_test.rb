require "test_helper"

class HumanInteractions::CompleteTaskTest < ActiveSupport::TestCase
  test "completes open human tasks and removes them from open scope" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Call the vendor and capture the ETA." }
    )

    completed = HumanInteractions::CompleteTask.call(
      human_task_request: request,
      completion_payload: { "eta" => "2026-03-26T09:00:00Z", "notes" => "Vendor confirmed dispatch." }
    )

    assert completed.resolved?
    assert_equal "completed", completed.resolution_kind
    assert_equal "Vendor confirmed dispatch.", completed.result_payload["notes"]
    assert completed.workflow_run.reload.ready?
    assert_not_includes HumanTaskRequest.open, completed
  end

  test "rejects late completion for pending delete conversations" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Call the vendor and capture the ETA." }
    )
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::CompleteTask.call(
        human_task_request: request,
        completion_payload: { "eta" => "2026-03-26T09:00:00Z" }
      )
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before resolving human interaction"
  end

  test "rejects completion for archived conversations" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Optional task" }
    )
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::CompleteTask.call(
        human_task_request: request,
        completion_payload: { "eta" => "2026-03-26T09:00:00Z" }
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before resolving human interaction"
  end

  test "rejects task completion while close is in progress" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Optional task" }
    )
    ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::CompleteTask.call(
        human_task_request: request,
        completion_payload: { "eta" => "2026-03-26T09:00:00Z" }
      )
    end

    assert_includes error.record.errors[:base], "must not resolve human interaction while close is in progress"
  end

  test "rejects stale task completion after the request has already been resolved" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Complete once" }
    )
    stale_request = HumanTaskRequest.find(request.id)

    HumanInteractions::CompleteTask.call(
      human_task_request: request,
      completion_payload: { "eta" => "2026-03-26T09:00:00Z" }
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::CompleteTask.call(
        human_task_request: stale_request,
        completion_payload: { "eta" => "2026-03-27T09:00:00Z" }
      )
    end

    assert_includes error.record.errors[:base], "must be open before task completion"
    assert_equal "2026-03-26T09:00:00Z", request.reload.result_payload["eta"]
    assert_equal 1,
      ConversationEvent.where(
        conversation: context[:conversation],
        event_kind: "human_interaction.resolved",
        stream_key: "human_interaction_request:#{request.id}"
      ).count
  end
end
