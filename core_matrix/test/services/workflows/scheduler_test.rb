require "test_helper"

class Workflows::SchedulerTest < ActiveSupport::TestCase
  test "barrier_all requires every incoming edge to be required and every required predecessor to complete durably" do
    workflow_run, nodes = create_merge_workflow!(
      left_requirement: "required",
      right_requirement: "required"
    )

    assert_equal ["root"], runnable_node_keys(workflow_run)

    complete_workflow_node!(nodes.fetch(:root))
    assert_equal %w[left right], runnable_node_keys(workflow_run).sort

    complete_workflow_node!(nodes.fetch(:left))
    refute_includes runnable_node_keys(workflow_run), "join"

    complete_workflow_node!(nodes.fetch(:right))
    assert_equal ["join"], runnable_node_keys(workflow_run)
  end

  test "any_of requires every incoming edge to be optional and becomes one-shot after the first arrival" do
    workflow_run, nodes = create_merge_workflow!(
      left_requirement: "optional",
      right_requirement: "optional"
    )

    assert_equal ["root"], runnable_node_keys(workflow_run)

    complete_workflow_node!(nodes.fetch(:root))
    assert_equal %w[left right], runnable_node_keys(workflow_run).sort

    complete_workflow_node!(nodes.fetch(:left))
    assert_includes runnable_node_keys(workflow_run), "join"

    queue_workflow_node!(nodes.fetch(:join))
    complete_workflow_node!(nodes.fetch(:right))
    refute_includes runnable_node_keys(workflow_run), "join"
  end

  test "mixed fan in requires all required predecessors and ignores late optional arrivals after the merge has been consumed" do
    workflow_run, nodes = create_merge_workflow!(
      left_requirement: "required",
      right_requirement: "optional"
    )

    assert_equal ["root"], runnable_node_keys(workflow_run)

    complete_workflow_node!(nodes.fetch(:root))
    assert_equal %w[left right], runnable_node_keys(workflow_run).sort

    complete_workflow_node!(nodes.fetch(:left))
    assert_includes runnable_node_keys(workflow_run), "join"

    queue_workflow_node!(nodes.fetch(:join))
    complete_workflow_node!(nodes.fetch(:right))
    refute_includes runnable_node_keys(workflow_run), "join"
  end

  test "reject policy leaves transcript state unchanged" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
    assert_equal output.public_id, restart_turn.origin_payload["expected_tail_message_id"]
    assert_equal turn.public_id, restart_turn.origin_payload["queued_from_turn_id"]
    assert stale_queued.reload.canceled?
    assert workflow_run.reload.waiting?
    assert_equal "policy_gate", workflow_run.wait_reason_kind
    assert_equal "restart", workflow_run.wait_reason_payload["policy_mode"]
    assert_equal restart_turn.public_id, workflow_run.wait_reason_payload["queued_turn_id"]
    assert_equal "Turn", workflow_run.blocking_resource_type
    assert_equal restart_turn.public_id, workflow_run.blocking_resource_id
    assert_not_nil workflow_run.waiting_since_at
  end

  test "restart policy reloads a cached-nil workflow association" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_nil turn.workflow_run

    workflow_run = create_workflow_run!(turn: Turn.find(turn.id))
    attach_selected_output!(turn, content: "Committed output")

    restart_turn = Workflows::Scheduler.apply_during_generation_policy(
      turn: turn,
      content: "Restart from stale turn",
      policy_mode: "restart"
    )

    assert restart_turn.queued?
    assert workflow_run.reload.waiting?
    assert_equal restart_turn.public_id, workflow_run.blocking_resource_id
  end

  test "cancels stale queued work when expected tail no longer matches" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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

  test "restart policy releases the matching policy gate when expected tail no longer matches" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    attach_selected_output!(turn, content: "Initial output")
    queued_turn = Workflows::Scheduler.apply_during_generation_policy(
      turn: turn,
      content: "Queued follow up",
      policy_mode: "restart"
    )
    attach_selected_output!(turn, content: "Newer output", variant_index: 1)

    guarded = Workflows::Scheduler.guard_expected_tail!(turn: queued_turn)

    assert guarded.canceled?
    assert workflow_run.reload.ready?
    assert_nil workflow_run.wait_reason_kind
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_nil workflow_run.waiting_since_at
    assert_nil workflow_run.blocking_resource_type
    assert_nil workflow_run.blocking_resource_id
  end

  def create_merge_workflow!(left_requirement:, right_requirement:)
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
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
          metadata: {},
        },
      ],
      edges: []
    )

    workflow_run = workflow_run.reload
    nodes = workflow_run.workflow_nodes.index_by(&:node_key)

    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: nodes.fetch("root"),
      to_node: nodes.fetch("left"),
      ordinal: 0
    )
    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: nodes.fetch("root"),
      to_node: nodes.fetch("right"),
      ordinal: 1
    )
    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: nodes.fetch("left"),
      to_node: nodes.fetch("join"),
      requirement: left_requirement,
      ordinal: 0
    )
    create_workflow_edge!(
      workflow_run: workflow_run,
      from_node: nodes.fetch("right"),
      to_node: nodes.fetch("join"),
      requirement: right_requirement,
      ordinal: 0
    )

    [workflow_run, nodes.symbolize_keys]
  end

  def complete_workflow_node!(workflow_node)
    workflow_node.update!(
      lifecycle_state: "completed",
      started_at: 1.minute.ago,
      finished_at: Time.current
    )
  end

  def queue_workflow_node!(workflow_node)
    workflow_node.update!(
      lifecycle_state: "queued",
      started_at: nil,
      finished_at: nil
    )
  end

  def runnable_node_keys(workflow_run)
    Workflows::Scheduler.call(workflow_run: workflow_run).map(&:node_key)
  end
end
