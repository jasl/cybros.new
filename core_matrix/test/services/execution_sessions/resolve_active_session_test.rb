require "test_helper"

class ExecutorSessions::ResolveActiveSessionTest < ActiveSupport::TestCase
  test "returns the active executor session for the program" do
    context = build_agent_control_context!

    assert_equal context[:executor_session], ExecutorSessions::ResolveActiveSession.call(
      executor_program: context[:executor_program]
    )

    context[:executor_session].update!(lifecycle_state: "stale")

    assert_nil ExecutorSessions::ResolveActiveSession.call(
      executor_program: context[:executor_program]
    )
  end
end
