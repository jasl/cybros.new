require "test_helper"

class WorkflowSchedulerFlowTest < ActionDispatch::IntegrationTest
  test "scheduler keeps joins blocked until predecessors finish and cancels stale queued follow up work" do
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Primary input",
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
          node_key: "left",
          node_type: "tool_call",
          decision_source: "agent_program",
          metadata: {},
        },
        {
          node_key: "right",
          node_type: "tool_call",
          decision_source: "agent_program",
          metadata: {},
        },
        {
          node_key: "join",
          node_type: "barrier_join",
          decision_source: "system",
          metadata: { "join_mode" => "barrier" },
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "left" },
        { from_node_key: "root", to_node_key: "right" },
        { from_node_key: "left", to_node_key: "join" },
        { from_node_key: "right", to_node_key: "join" },
      ]
    )
    initial = Workflows::Scheduler.call(workflow_run: workflow_run)
    after_root = Workflows::Scheduler.call(
      workflow_run: workflow_run,
      satisfied_node_keys: ["root"]
    )
    after_join = Workflows::Scheduler.call(
      workflow_run: workflow_run,
      satisfied_node_keys: ["root", "left", "right"]
    )
    attach_selected_output!(turn, content: "Committed output")
    queued_turn = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued follow up",
      policy_mode: "queue"
    )
    attach_selected_output!(turn, content: "Newer committed output", variant_index: 1)

    guarded_queued_turn = Workflows::Scheduler.guard_expected_tail!(turn: queued_turn)

    assert_equal ["root"], initial.map(&:node_key)
    assert_equal %w[left right], after_root.map(&:node_key).sort
    assert_equal ["join"], after_join.map(&:node_key)
    assert guarded_queued_turn.canceled?
  end
end
