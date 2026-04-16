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

  test "enqueues execute node jobs with queue timing metadata" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})

    assert_enqueued_with(
      job: Workflows::ExecuteNodeJob,
      queue: "llm_dev",
      args: ->(job_args) do
        job_args.first == workflow_run.workflow_nodes.find_by!(node_key: "turn_step").public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:queue_name] == "llm_dev" &&
          Time.iso8601(job_args.second.fetch(:enqueued_at_iso8601)).is_a?(Time)
      rescue ArgumentError, KeyError
        false
      end
    ) do
      Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run.reload)
    end
  end

  test "enqueues tool call nodes onto the tool_calls queue" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Dispatch input",
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
          decision_source: "agent",
          metadata: {},
          tool_call_payload: {
            "call_id" => "call-1",
            "tool_name" => "compact_context",
            "arguments" => {
              "messages" => [
                { "role" => "user", "content" => "a" },
                { "role" => "assistant", "content" => "b" },
              ],
              "budget_hints" => {},
            },
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

  test "enqueues prompt compaction nodes onto the workflow default queue" do
    context = build_agent_control_context!(workflow_node_key: "prompt_compaction_node", workflow_node_type: "prompt_compaction")
    workflow_node = context.fetch(:workflow_node)

    assert_enqueued_with(job: Workflows::ExecuteNodeJob, queue: "workflow_default") do
      Workflows::DispatchRunnableNodes.call(
        workflow_run: context.fetch(:workflow_run),
        runnable_nodes: [workflow_node]
      )
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
