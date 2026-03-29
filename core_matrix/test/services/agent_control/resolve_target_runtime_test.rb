require "test_helper"

class AgentControl::ResolveTargetRuntimeTest < ActiveSupport::TestCase
  test "routes agent-plane work to the explicitly targeted deployment" do
    context = build_agent_control_context!
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: context[:agent_installation],
      target_agent_deployment: context[:deployment]
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "agent", result.runtime_plane
    assert_nil result.execution_environment
    assert_equal context[:deployment], result.delivery_endpoint
    assert result.matches?(context[:deployment])
  end

  test "routes environment-plane work by execution environment instead of installation hints" do
    context = build_agent_control_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: other_agent_installation,
      target_execution_environment: context[:execution_environment],
      item_type: "resource_close_request",
      runtime_plane: "environment",
      target_kind: "agent_installation",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    result = AgentControl::ResolveTargetRuntime.call(mailbox_item: mailbox_item)

    assert_equal "environment", result.runtime_plane
    assert_equal context[:execution_environment], result.execution_environment
    assert_equal context[:deployment], result.delivery_endpoint
    assert result.matches?(context[:deployment])
  end
end
