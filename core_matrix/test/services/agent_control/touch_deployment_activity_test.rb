require "test_helper"

class AgentControl::TouchDeploymentActivityTest < ActiveSupport::TestCase
  test "marks deployment activity as active at the provided timestamp" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 20:00:00 UTC")

    result = AgentControl::TouchDeploymentActivity.call(
      deployment: context[:deployment],
      occurred_at: occurred_at
    )

    assert_equal context[:deployment], result
    assert_equal "active", result.reload.control_activity_state
    assert_equal occurred_at, result.last_control_activity_at
  end
end
