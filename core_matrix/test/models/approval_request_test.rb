require "test_helper"

class ApprovalRequestTest < ActiveSupport::TestCase
  test "requires approval scope and only allows approval outcomes" do
    context = build_human_interaction_context!

    request = ApprovalRequest.new(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      agent: context[:agent],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: true,
      request_payload: { "approval_scope" => "publish" },
      result_payload: {}
    )

    assert request.valid?

    missing_scope = request.dup
    missing_scope.request_payload = {}
    assert_not missing_scope.valid?
    assert_includes missing_scope.errors[:request_payload], "must include approval_scope"

    resolved = request.dup
    resolved.request_payload = request.request_payload
    resolved.lifecycle_state = "resolved"
    resolved.resolution_kind = "approved"
    resolved.resolved_at = Time.current
    assert resolved.valid?

    invalid_resolution = resolved.dup
    invalid_resolution.resolution_kind = "submitted"
    assert_not invalid_resolution.valid?
    assert_includes invalid_resolution.errors[:resolution_kind], "must be approved or denied for approval requests"
  end
end
