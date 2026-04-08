require "test_helper"

class Workflows::DispatchRunnableNodesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues llm turn steps onto the resolved provider queue" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})

    assert_equal "dev", workflow_run.turn.resolved_provider_handle

    assert_enqueued_with(job: Workflows::ExecuteNodeJob, queue: "llm_dev") do
      Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run.reload)
    end
  end

  test "enqueues tool call nodes onto the tool_calls queue" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Dispatch input",
      agent_program_version: context[:agent_program_version],
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
          node_key: "tool_node",
          node_type: "tool_call",
          decision_source: "agent_program",
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-1",
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
          },
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "tool_node" },
      ]
    )

    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "root"))

    assert_enqueued_with(job: Workflows::ExecuteNodeJob, queue: "tool_calls") do
      Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run.reload)
    end
  end

  private

  def complete_workflow_node!(workflow_node)
    workflow_node.update!(
      lifecycle_state: "completed",
      started_at: Time.current,
      finished_at: Time.current
    )
  end
end
