require "test_helper"

class RuntimeProcessFlowTest < ActionDispatch::IntegrationTest
  test "background process runs retain workflow provenance and replay status through node events" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Run process",
      agent_snapshot: context[:agent_snapshot],
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
          node_type: "background_service",
          decision_source: "agent",
          metadata: { "policy_sensitive" => true },
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "process" },
      ]
    )
    process_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "process")

    process_run = Processes::Provision.call(
      workflow_node: process_node,
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      command_line: "echo hi",
      origin_message: turn.selected_input_message
    ).process_run
    Processes::Activate.call(process_run: process_run)
    stopped = Processes::Exit.call(process_run: process_run, lifecycle_state: "stopped", reason: "completed")

    assert_equal conversation, stopped.conversation
    assert_equal turn, stopped.turn
    assert_equal turn.selected_input_message, stopped.origin_message
    assert_equal context[:execution_runtime], stopped.execution_runtime
    assert_equal %w[starting running stopped], WorkflowNodeEvent.where(workflow_node: process_node, event_kind: "status").order(:ordinal).map { |event| event.payload.fetch("state") }
    assert_equal "background_service", AuditLog.find_by!(action: "process_run.started").metadata["kind"]
  end
end
