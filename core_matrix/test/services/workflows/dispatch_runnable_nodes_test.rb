require "test_helper"

class Workflows::DispatchRunnableNodesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues one job for one runnable workflow node instead of collapsing the workflow into a single unit" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Dispatch input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "leaf",
          node_type: "turn_step",
          decision_source: "agent_program",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "leaf" },
      ]
    )

    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "root"))

    assert_enqueued_jobs 1 do
      Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run.reload)
    end
  end

  private

  def complete_workflow_node!(workflow_node)
    workflow_node.update!(
      lifecycle_state: "completed",
      started_at: 1.minute.ago,
      finished_at: Time.current
    )
  end
end
