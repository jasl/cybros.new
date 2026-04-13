require "test_helper"

class Turns::MaterializeAndDispatchJobTest < ActiveSupport::TestCase
  test "materializes the pending turn by public id" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Follow up",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    assert_difference("WorkflowRun.count", +1) do
      Turns::MaterializeAndDispatchJob.perform_now(turn.public_id)
    end

    assert_equal "ready", turn.reload.workflow_bootstrap_state
  end

  test "ignores a missing turn id" do
    assert_nil Turns::MaterializeAndDispatchJob.perform_now("turn_missing")
  end
end
