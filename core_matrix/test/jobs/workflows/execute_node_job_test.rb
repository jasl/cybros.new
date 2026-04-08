require "test_helper"

class Workflows::ExecuteNodeJobTest < ActiveSupport::TestCase
  test "uses workflow_default as the fallback queue" do
    assert_equal "workflow_default", Workflows::ExecuteNodeJob.queue_name
  end

  test "skips a workflow node that is already terminal" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Node job input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(
      turn: turn,
      lifecycle_state: "active"
    )
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "node",
      node_type: "turn_step",
      decision_source: "agent_program",
      metadata: {}
    )

    complete_workflow_node!(workflow_node)

    assert_equal "completed", workflow_node.reload.lifecycle_state

    Workflows::ExecuteNodeJob.perform_now(workflow_node.public_id)

    assert_equal "completed", workflow_node.reload.lifecycle_state
  end

  test "skips a workflow node when its workflow run is waiting" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Node job input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(
      turn: turn,
      lifecycle_state: "active",
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_failure_kind: "provider_overloaded",
      wait_retry_scope: "step",
      wait_retry_strategy: "automatic",
      wait_attempt_no: 1,
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: "node-1"
    )
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "node",
      node_type: "turn_step",
      decision_source: "agent_program",
      metadata: {}
    )

    original_call = Workflows::ExecuteNode.method(:call)
    Workflows::ExecuteNode.singleton_class.define_method(:call) do |**|
      raise "should not execute waiting workflow nodes"
    end

    begin
      Workflows::ExecuteNodeJob.perform_now(workflow_node.public_id)
    ensure
      Workflows::ExecuteNode.singleton_class.define_method(:call, original_call)
    end

    assert_equal "pending", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_run.reload.wait_state
  end

  test "swallows stale execution errors raised by queued background work" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Node job input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(
      turn: turn,
      lifecycle_state: "active"
    )
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "node",
      node_type: "turn_step",
      decision_source: "agent_program",
      metadata: {}
    )

    original_call = Workflows::ExecuteNode.method(:call)
    Workflows::ExecuteNode.singleton_class.define_method(:call) do |**|
      raise ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError, "provider execution result is stale"
    end

    Workflows::ExecuteNodeJob.perform_now(workflow_node.public_id)

    assert_equal "pending", workflow_node.reload.lifecycle_state
  ensure
    Workflows::ExecuteNode.singleton_class.define_method(:call, original_call) if original_call
  end

  private

  def complete_workflow_node!(workflow_node)
    workflow_node.update!(
      lifecycle_state: "completed",
      started_at: 1.minute.ago,
      finished_at: Time.current
    )
  end
end
