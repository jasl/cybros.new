require "test_helper"

class ExecutionRuntimeConnections::ResolveActiveConnectionTest < ActiveSupport::TestCase
  test "returns the active execution runtime connection for the agent" do
    context = build_agent_control_context!

    assert_equal context[:execution_runtime_connection], ExecutionRuntimeConnections::ResolveActiveConnection.call(
      execution_runtime: context[:execution_runtime]
    )

    context[:execution_runtime_connection].update!(lifecycle_state: "stale")

    assert_nil ExecutionRuntimeConnections::ResolveActiveConnection.call(
      execution_runtime: context[:execution_runtime]
    )
  end
end
