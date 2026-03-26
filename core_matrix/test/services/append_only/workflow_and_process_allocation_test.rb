require "test_helper"

class AppendOnly::WorkflowAndProcessAllocationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { truncate_all_tables! }
  teardown { truncate_all_tables! }

  test "allocates unique workflow node and edge ordinals across concurrent mutations" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
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

    assert_parallel_success!(
      run_in_parallel(4) do |index|
        Workflows::Mutate.call(
          workflow_run: WorkflowRun.find(workflow_run.id),
          nodes: [
            {
              node_key: "node_#{index}",
              node_type: "tool_call",
              decision_source: "agent_program",
              metadata: {},
            },
          ],
          edges: [
            { from_node_key: "root", to_node_key: "node_#{index}" },
          ]
        )
      end
    )

    reloaded_run = workflow_run.reload
    root_node = reloaded_run.workflow_nodes.find_by!(node_key: "root")

    assert_equal (0..4).to_a, reloaded_run.workflow_nodes.order(:ordinal).pluck(:ordinal)
    assert_equal (0..3).to_a, reloaded_run.workflow_edges.where(from_node: root_node).order(:ordinal).pluck(:ordinal)
  end

  test "allocates unique workflow node event ordinals across concurrent process starts" do
    process_context = build_process_context!
    workflow_node = process_context[:workflow_node]
    execution_environment_id = process_context[:execution_environment].id
    origin_message_id = process_context[:origin_message].id

    process_runs = assert_parallel_success!(
      run_in_parallel(5) do |index|
        Processes::Start.call(
          workflow_node: WorkflowNode.find(workflow_node.id),
          execution_environment: ExecutionEnvironment.find(execution_environment_id),
          kind: "turn_command",
          command_line: "echo #{index}",
          timeout_seconds: 30,
          origin_message: Message.find(origin_message_id)
        )
      end
    )

    assert_equal 5, process_runs.size
    assert_equal (0..4).to_a, WorkflowNodeEvent.where(workflow_node: workflow_node).order(:ordinal).pluck(:ordinal)
  end

  test "allocates unique workflow node event ordinals across concurrent process stops" do
    process_context = build_process_context!
    process_runs = 4.times.map do |index|
      Processes::Start.call(
        workflow_node: process_context[:workflow_node],
        execution_environment: process_context[:execution_environment],
        kind: "background_service",
        command_line: "bin/service_#{index}",
        origin_message: process_context[:origin_message]
      )
    end

    stopped_runs = assert_parallel_success!(
      run_parallel_operations(
        *process_runs.map.with_index do |process_run, index|
          proc do
            Processes::Stop.call(
              process_run: ProcessRun.find(process_run.id),
              reason: "stop_#{index}"
            )
          end
        end
      )
    )

    assert_equal 4, stopped_runs.count(&:stopped?)
    assert_equal (0..7).to_a, WorkflowNodeEvent.where(workflow_node: process_context[:workflow_node]).order(:ordinal).pluck(:ordinal)
  end

  private

  def build_process_context!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Process input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run, metadata: {})

    {
      conversation: conversation,
      execution_environment: context[:execution_environment],
      origin_message: turn.selected_input_message,
      turn: turn,
      workflow_node: workflow_node,
    }.merge(context)
  end
end
