require "test_helper"

module AgentSnapshots
end

class AgentSnapshots::RecordHeartbeatTest < ActiveSupport::TestCase
  test "updates the live agent connection heartbeat state" do
    registration = register_agent_runtime!

    travel_to Time.zone.parse("2026-03-24 10:15:00 UTC") do
      AgentSnapshots::RecordHeartbeat.call(
        agent_connection: registration[:agent_connection],
        health_status: "healthy",
        health_metadata: { "latency_ms" => 82 },
        auto_resume_eligible: true
      )
    end

    agent_connection = registration[:agent_connection].reload

    assert agent_connection.healthy?
    assert_equal({ "latency_ms" => 82 }, agent_connection.health_metadata)
    assert_equal Time.zone.parse("2026-03-24 10:15:00 UTC"), agent_connection.last_heartbeat_at
    assert_equal Time.zone.parse("2026-03-24 10:15:00 UTC"), agent_connection.last_health_check_at
    assert agent_connection.auto_resume_eligible?
  end

  test "agent snapshot lookup resolves through the active agent connection" do
    registration = register_agent_runtime!

    result = AgentSnapshots::RecordHeartbeat.call(
      agent_snapshot: registration[:agent_snapshot],
      health_status: "degraded",
      health_metadata: { "source" => "external-fenix" },
      auto_resume_eligible: false,
      unavailability_reason: "high_load"
    )

    assert_equal registration[:agent_connection], result
    assert result.degraded?
    assert_equal "high_load", result.unavailability_reason
  end
end
