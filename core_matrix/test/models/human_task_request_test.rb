require "test_helper"

class HumanTaskRequestTest < ActiveSupport::TestCase
  test "requires instructions and exposes open scope" do
    context = build_human_interaction_context!

    open_request = HumanTaskRequest.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: false,
      request_payload: { "instructions" => "Call the vendor and confirm delivery." },
      result_payload: {}
    )
    completed_request = HumanTaskRequest.create!(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "resolved",
      resolution_kind: "completed",
      resolved_at: Time.current,
      blocking: false,
      request_payload: { "instructions" => "Archive the ticket." },
      result_payload: { "completed" => true }
    )

    assert_equal [open_request], HumanTaskRequest.open.to_a
    assert_not_includes HumanTaskRequest.open, completed_request

    invalid_request = HumanTaskRequest.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: false,
      request_payload: {},
      result_payload: {}
    )

    assert_not invalid_request.valid?
    assert_includes invalid_request.errors[:request_payload], "must include instructions"
  end
end
