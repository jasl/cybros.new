require "test_helper"

class AgentControl::HandleHealthReportTest < ActiveSupport::TestCase
  test "updates agent_snapshot health state and metadata" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 19:00:00 UTC")

    AgentControl::HandleHealthReport.call(
      agent_snapshot: context[:agent_snapshot],
      payload: {
        "health_status" => "degraded",
        "health_metadata" => { "reason" => "high_load" },
      },
      occurred_at: occurred_at
    )

    assert_equal "degraded", context[:agent_snapshot].reload.health_status
    assert_equal({ "reason" => "high_load" }, context[:agent_snapshot].health_metadata)
    assert_equal occurred_at, context[:agent_snapshot].last_health_check_at
  end
end
