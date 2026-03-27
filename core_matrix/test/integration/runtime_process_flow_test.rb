require "test_helper"

class RuntimeProcessFlowTest < ActionDispatch::IntegrationTest
  test "workflow process runs remain node-owned and replay status through node events" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Run process",
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
          node_key: "process",
          node_type: "turn_command",
          decision_source: "agent_program",
          metadata: { "policy_sensitive" => true },
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "process" },
      ]
    )
    process_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "process")

    process_run = Processes::Start.call(
      workflow_node: process_node,
      execution_environment: context[:execution_environment],
      kind: "turn_command",
      command_line: "echo hi",
      timeout_seconds: 30,
      origin_message: turn.selected_input_message
    )
    stopped = Processes::Stop.call(process_run: process_run, reason: "completed")

    assert_equal conversation, stopped.conversation
    assert_equal turn, stopped.turn
    assert_equal turn.selected_input_message, stopped.origin_message
    assert_equal context[:execution_environment], stopped.execution_environment
    assert_equal %w[running stopped], WorkflowNodeEvent.where(workflow_node: process_node, event_kind: "status").order(:ordinal).map { |event| event.payload.fetch("state") }
    assert_equal "turn_command", AuditLog.find_by!(action: "process_run.started").metadata["kind"]
  end
end
