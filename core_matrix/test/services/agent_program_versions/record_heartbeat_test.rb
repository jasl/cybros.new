require "test_helper"

module AgentProgramVersions
end

class AgentProgramVersions::RecordHeartbeatTest < ActiveSupport::TestCase
  test "updates the live agent session heartbeat state" do
    registration = register_agent_runtime!

    travel_to Time.zone.parse("2026-03-24 10:15:00 UTC") do
      AgentProgramVersions::RecordHeartbeat.call(
        agent_session: registration[:agent_session],
        health_status: "healthy",
        health_metadata: { "latency_ms" => 82 },
        auto_resume_eligible: true
      )
    end

    agent_session = registration[:agent_session].reload

    assert agent_session.healthy?
    assert_equal({ "latency_ms" => 82 }, agent_session.health_metadata)
    assert_equal Time.zone.parse("2026-03-24 10:15:00 UTC"), agent_session.last_heartbeat_at
    assert_equal Time.zone.parse("2026-03-24 10:15:00 UTC"), agent_session.last_health_check_at
    assert agent_session.auto_resume_eligible?
  end

  test "deployment lookup resolves through the active agent session" do
    registration = register_agent_runtime!

    result = AgentProgramVersions::RecordHeartbeat.call(
      deployment: registration[:deployment],
      health_status: "degraded",
      health_metadata: { "source" => "external-fenix" },
      auto_resume_eligible: false,
      unavailability_reason: "high_load"
    )

    assert_equal registration[:agent_session], result
    assert result.degraded?
    assert_equal "high_load", result.unavailability_reason
  end
end
