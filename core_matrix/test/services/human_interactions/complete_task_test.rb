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
end
