require "test_helper"

class Turns::MaterializeWorkflowBootstrapTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "materializes workflow substrate and dispatches the pending turn" do
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

    workflow_run = nil

    assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
      assert_difference(["WorkflowRun.count", "WorkflowNode.count"], +1) do
        workflow_run = Turns::MaterializeWorkflowBootstrap.call(turn: turn)
      end
    end

    assert_equal workflow_run, turn.reload.workflow_run
    assert_equal "ready", turn.workflow_bootstrap_state
    assert turn.workflow_bootstrap_started_at.present?
    assert turn.workflow_bootstrap_finished_at.present?
    assert_equal "candidate:codex_subscription/gpt-5.3-codex",
      turn.resolved_model_selection_snapshot.fetch("normalized_selector")
    assert_equal workflow_run, conversation.reload.latest_active_workflow_run
  end

  test "does not recreate workflow substrate when the turn is already ready" do
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
    workflow_run = Turns::MaterializeWorkflowBootstrap.call(turn: turn)

    assert_no_difference(["WorkflowRun.count", "WorkflowNode.count"]) do
      assert_equal workflow_run, Turns::MaterializeWorkflowBootstrap.call(turn: turn.reload)
    end
  end

  test "marks the turn failed and projects failed supervision state when workflow materialization raises" do
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

    original_call = Workflows::CreateForTurn.method(:call)
    Workflows::CreateForTurn.singleton_class.define_method(:call) do |**|
      raise RuntimeError, "selector resolution blew up"
    end

    assert_no_difference(["WorkflowRun.count", "WorkflowNode.count"]) do
      assert_nil Turns::MaterializeWorkflowBootstrap.call(turn: turn)
    end

    turn.reload
    assert_equal "failed", turn.workflow_bootstrap_state
    assert_equal "RuntimeError", turn.workflow_bootstrap_failure_payload.fetch("error_class")
    assert_equal "selector resolution blew up", turn.workflow_bootstrap_failure_payload.fetch("error_message")

    state = conversation.reload.conversation_supervision_state
    assert_equal "failed", state.overall_state
    assert_equal "failed", state.board_lane
    assert_equal turn.public_id, state.current_owner_public_id
    assert_equal "selector resolution blew up", state.recent_progress_summary
  ensure
    Workflows::CreateForTurn.singleton_class.define_method(:call, original_call) if original_call
  end
end
