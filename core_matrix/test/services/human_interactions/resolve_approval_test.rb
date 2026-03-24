require "test_helper"

class HumanInteractions::ResolveApprovalTest < ActiveSupport::TestCase
  test "records approval outcome and resumes the same workflow run by default" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )

    resolved = HumanInteractions::ResolveApproval.call(
      approval_request: request,
      decision: "approved",
      result_payload: { "comment" => "Ship it." }
    )

    assert resolved.resolved?
    assert_equal "approved", resolved.resolution_kind
    assert_equal true, resolved.result_payload["approved"]
    assert_equal "Ship it.", resolved.result_payload["comment"]
    assert_equal context[:workflow_run].id, resolved.workflow_run_id
    assert resolved.workflow_run.reload.ready?

    live_projection = ConversationEvent.live_projection(conversation: context[:conversation])
    assert_equal 1, live_projection.size
    assert_equal "human_interaction.resolved", live_projection.first.event_kind
    assert_equal 1, live_projection.first.stream_revision

    assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::ResolveApproval.call(
        approval_request: resolved.reload,
        decision: "denied"
      )
    end
  end
end
