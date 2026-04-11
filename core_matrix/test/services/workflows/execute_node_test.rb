require "test_helper"

class Workflows::ExecuteNodeTest < ActiveSupport::TestCase
  test "forwards catalog overrides into turn step execution" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Node input",
      agent_snapshot: context[:agent_snapshot],
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
      decision_source: "agent",
      metadata: {}
    )

    captured = nil
    original_call = ProviderExecution::ExecuteTurnStep.method(:call)
    ProviderExecution::ExecuteTurnStep.singleton_class.define_method(:call) do |**kwargs|
      captured = kwargs
      :ok
    end

    Workflows::ExecuteNode.call(
      workflow_node: workflow_node,
      messages: [{ "role" => "user", "content" => "hello" }],
      catalog: :catalog_override
    )

    assert_equal :catalog_override, captured.fetch(:catalog)
    assert_equal workflow_node.public_id, captured.fetch(:workflow_node).public_id
  ensure
    ProviderExecution::ExecuteTurnStep.singleton_class.define_method(:call, original_call) if original_call
  end
end
