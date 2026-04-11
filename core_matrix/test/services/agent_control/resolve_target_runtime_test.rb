require "test_helper"

class AgentControl::ResolveTargetRuntimeTest < ActiveSupport::TestCase
  test "routes agent-plane work to the explicitly targeted agent connection" do
    context = build_agent_control_context!
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: context[:agent],
      target_agent_snapshot: context[:agent_snapshot]
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "agent", result.control_plane
    assert_nil result.execution_runtime
    assert_equal context[:agent_connection], result.delivery_endpoint
    assert result.matches?(context[:agent_snapshot])
  end

  test "routes execution-runtime-plane work by execution runtime instead of agent hints" do
    context = build_agent_control_context!
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "execution_runtime", result.control_plane
    assert_equal context[:execution_runtime], result.execution_runtime
    assert_equal context[:execution_runtime_connection], result.delivery_endpoint
    assert result.matches?(context[:execution_runtime_connection])
    refute result.matches?(context[:agent_snapshot])
  end
end
