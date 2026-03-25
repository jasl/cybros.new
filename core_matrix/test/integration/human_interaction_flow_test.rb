require "test_helper"

class HumanInteractionFlowTest < ActionDispatch::IntegrationTest
  test "blocking approval resolution resumes the same workflow run and keeps append-only conversation event history" do
    context = build_human_interaction_context!
    workflow_run = context[:workflow_run]

    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )

    assert_equal [], Workflows::Scheduler.call(workflow_run: workflow_run.reload)

    resolved = HumanInteractions::ResolveApproval.call(
      approval_request: request,
      decision: "approved"
    )

    assert_equal workflow_run.id, resolved.workflow_run_id
    assert_equal context[:turn], resolved.turn
    assert_equal ["root"], Workflows::Scheduler.call(workflow_run: workflow_run.reload).map(&:node_key)
    assert_equal %w[human_interaction.opened human_interaction.resolved], ConversationEvent.where(conversation: context[:conversation]).order(:projection_sequence).pluck(:event_kind)
    assert_equal ["human_interaction.resolved"], ConversationEvent.live_projection(conversation: context[:conversation]).map(&:event_kind)
  end
end
