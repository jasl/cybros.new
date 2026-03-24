require "test_helper"

class Workflows::SchedulerTest < ActiveSupport::TestCase
  test "selects runnable nodes for fan out and barrier join semantics" do
    workflow_run, node_keys = create_barrier_workflow!

    initial = Workflows::Scheduler.call(workflow_run: workflow_run)
    after_root = Workflows::Scheduler.call(
      workflow_run: workflow_run,
      satisfied_node_keys: ["root"]
    )
    after_left_only = Workflows::Scheduler.call(
      workflow_run: workflow_run,
      satisfied_node_keys: ["root", "left"]
    )
    after_both = Workflows::Scheduler.call(
      workflow_run: workflow_run,
      satisfied_node_keys: ["root", "left", "right"]
    )

    assert_equal ["root"], initial.map(&:node_key)
    assert_equal %w[left right], after_root.map(&:node_key).sort
    assert_equal ["right"], after_left_only.map(&:node_key)
    assert_equal ["join"], after_both.map(&:node_key)
    assert_equal node_keys.sort, workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key).sort
  end

  test "reject policy leaves transcript state unchanged" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_workflow_run!(turn: turn)
    attach_selected_output!(turn, content: "Streaming output")

    assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::Scheduler.apply_during_generation_policy(
        turn: turn,
        content: "Blocked follow up",
        policy_mode: "reject"
      )
    end

    assert_equal ["Original input"], UserMessage.where(turn: turn).order(:variant_index).pluck(:content)
    assert_equal 1, conversation.turns.count
  end

  test "restart policy records wait state and clears older queued follow up work" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    output = attach_selected_output!(turn, content: "Committed output")
    stale_queued = Turns::QueueFollowUp.call(
      conversation: conversation,
      content: "Older queued follow up",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    restart_turn = Workflows::Scheduler.apply_during_generation_policy(
      turn: turn,
      content: "Newest restart input",
      policy_mode: "restart"
    )

    assert restart_turn.queued?
    assert_equal "restart", restart_turn.origin_payload["during_generation_policy"]
    assert_equal output.id.to_s, restart_turn.origin_payload["expected_tail_message_id"]
    assert stale_queued.reload.canceled?
    assert workflow_run.reload.waiting?
    assert_equal "policy_gate", workflow_run.wait_reason_kind
    assert_equal "restart", workflow_run.wait_reason_payload["policy_mode"]
    assert_equal "Turn", workflow_run.blocking_resource_type
    assert_equal restart_turn.id.to_s, workflow_run.blocking_resource_id
    assert_not_nil workflow_run.waiting_since_at
  end

  test "cancels stale queued work when expected tail no longer matches" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_workflow_run!(turn: turn)
    attach_selected_output!(turn, content: "Initial output")
    queued_turn = Workflows::Scheduler.apply_during_generation_policy(
      turn: turn,
      content: "Queued follow up",
      policy_mode: "queue"
    )
    attach_selected_output!(turn, content: "Newer output", variant_index: 1)

    guarded = Workflows::Scheduler.guard_expected_tail!(turn: queued_turn)

    assert guarded.canceled?
  end

  private

  def create_barrier_workflow!
    context = prepare_workflow_execution_context!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Graph input",
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

    [workflow_run, %w[root left right join]]
  end
end
