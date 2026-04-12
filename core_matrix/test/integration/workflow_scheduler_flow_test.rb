require "test_helper"

class WorkflowSchedulerFlowTest < ActionDispatch::IntegrationTest
  test "scheduler only releases a barrier_all merge after both required predecessors complete" do
    workflow_run = create_merge_workflow!(
      left_requirement: "required",
      right_requirement: "required"
    )

    initial = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "root"))
    after_root = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "left"))
    after_left = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "right"))
    after_right = Workflows::Scheduler.call(workflow_run: workflow_run)

    assert_equal ["root"], initial.map(&:node_key)
    assert_equal %w[left right], after_root.map(&:node_key).sort
    refute_includes after_left.map(&:node_key), "join"
    assert_equal ["join"], after_right.map(&:node_key)
  end

  test "scheduler releases an any_of merge after the first optional predecessor completes" do
    workflow_run = create_merge_workflow!(
      left_requirement: "optional",
      right_requirement: "optional"
    )

    initial = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "root"))
    after_root = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "right"))
    after_first_optional = Workflows::Scheduler.call(workflow_run: workflow_run)

    assert_equal ["root"], initial.map(&:node_key)
    assert_equal %w[left right], after_root.map(&:node_key).sort
    assert_includes after_first_optional.map(&:node_key), "join"
  end

  test "scheduler treats mixed fan in as one-shot and ignores late optional arrivals after the merge node is consumed" do
    workflow_run = create_merge_workflow!(
      left_requirement: "required",
      right_requirement: "optional"
    )

    initial = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "root"))
    after_root = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "right"))
    after_optional = Workflows::Scheduler.call(workflow_run: workflow_run)
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "left"))
    after_left = Workflows::Scheduler.call(workflow_run: workflow_run)
    queue_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "join"))
    complete_workflow_node!(workflow_run.workflow_nodes.find_by!(node_key: "right")) unless workflow_run.workflow_nodes.find_by!(node_key: "right").completed?
    after_late_optional = Workflows::Scheduler.call(workflow_run: workflow_run)

    assert_equal ["root"], initial.map(&:node_key)
    assert_equal %w[left right], after_root.map(&:node_key).sort
    refute_includes after_optional.map(&:node_key), "join"
    assert_includes after_left.map(&:node_key), "join"
    refute_includes after_late_optional.map(&:node_key), "join"
  end

  private

  def create_merge_workflow!(left_requirement:, right_requirement:)
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Primary input",
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
          decision_source: "agent",
          metadata: {},
        },
        {
          node_key: "right",
          node_type: "tool_call",
          decision_source: "agent",
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

    workflow_run
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
end
