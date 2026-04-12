require "test_helper"

class AgentControl::TouchAgentConnectionActivityTest < ActiveSupport::TestCase
  test "marks agent connection control activity at the provided timestamp" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 20:00:00 UTC")

    result = AgentControl::TouchAgentConnectionActivity.call(
      agent_definition_version: context[:agent_definition_version],
      occurred_at: occurred_at
    )

    assert_equal context[:agent_connection], result
    assert_equal "active_control", result.reload.control_activity_state
    assert_equal occurred_at, result.last_control_activity_at
  end
end
