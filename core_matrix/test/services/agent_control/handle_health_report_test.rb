require "test_helper"

class AgentControl::HandleHealthReportTest < ActiveSupport::TestCase
  test "updates deployment health state and metadata" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 19:00:00 UTC")

    AgentControl::HandleHealthReport.call(
      deployment: context[:deployment],
      payload: {
        "health_status" => "degraded",
        "health_metadata" => { "reason" => "high_load" },
      },
      occurred_at: occurred_at
    )

    assert_equal "degraded", context[:deployment].reload.health_status
    assert_equal({ "reason" => "high_load" }, context[:deployment].health_metadata)
    assert_equal occurred_at, context[:deployment].last_health_check_at
  end
end
