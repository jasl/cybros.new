require "test_helper"

class RuntimeProcessFlowTest < ActionDispatch::IntegrationTest
  test "background process runs retain workflow provenance and replay status through node events" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Run process",
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
          node_key: "process",
          node_type: "background_service",
          decision_source: "agent_program",
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
      executor_program: context[:executor_program],
      kind: "background_service",
      command_line: "echo hi",
      origin_message: turn.selected_input_message
    ).process_run
    Processes::Activate.call(process_run: process_run)
    stopped = Processes::Exit.call(process_run: process_run, lifecycle_state: "stopped", reason: "completed")

    assert_equal conversation, stopped.conversation
    assert_equal turn, stopped.turn
    assert_equal turn.selected_input_message, stopped.origin_message
    assert_equal context[:executor_program], stopped.executor_program
    assert_equal %w[starting running stopped], WorkflowNodeEvent.where(workflow_node: process_node, event_kind: "status").order(:ordinal).map { |event| event.payload.fetch("state") }
    assert_equal "background_service", AuditLog.find_by!(action: "process_run.started").metadata["kind"]
  end
end
