require "test_helper"

class ExecutionSessions::ResolveActiveSessionTest < ActiveSupport::TestCase
  test "returns the active execution session for the runtime" do
    context = build_agent_control_context!

    assert_equal context[:execution_session], ExecutionSessions::ResolveActiveSession.call(
      execution_runtime: context[:execution_runtime]
    )

    context[:execution_session].update!(lifecycle_state: "stale")

    assert_nil ExecutionSessions::ResolveActiveSession.call(
      execution_runtime: context[:execution_runtime]
    )
  end
end
