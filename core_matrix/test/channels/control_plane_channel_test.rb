require "test_helper"
require "action_cable/channel/test_case"

class ControlPlaneChannelTest < ActionCable::Channel::TestCase
  tests ControlPlaneChannel

  test "subscribes an authenticated agent definition version to its control stream" do
    context = build_agent_control_context!

    stub_connection(
      current_agent_definition_version: context[:agent_definition_version],
      current_agent_connection: context[:agent_connection],
      current_execution_runtime_connection: nil
    )

    subscribe

    assert subscription.confirmed?
    assert_has_stream AgentControl::StreamName.for_agent_definition_version(context[:agent_definition_version])
  end

  test "subscribes an authenticated execution runtime connection to its control stream" do
    context = build_agent_control_context!

    stub_connection(
      current_agent_definition_version: nil,
      current_agent_connection: nil,
      current_execution_runtime_connection: context[:execution_runtime_connection]
    )

    subscribe

    assert subscription.confirmed?
    assert_has_stream AgentControl::StreamName.for_execution_runtime_connection(context[:execution_runtime_connection])
  end

  test "rejects subscriptions without an authenticated control-plane identity" do
    stub_connection(
      current_agent_definition_version: nil,
      current_agent_connection: nil,
      current_execution_runtime_connection: nil
    )

    subscribe

    assert subscription.rejected?
  end
end
