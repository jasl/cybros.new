require "test_helper"

module AgentDeployments
end

class AgentDeployments::RecordHeartbeatTest < ActiveSupport::TestCase
  test "marks a pending deployment active and records heartbeat state" do
    deployment = create_agent_deployment!(
      bootstrap_state: "pending",
      health_status: "offline",
      health_metadata: {}
    )

    travel_to Time.zone.parse("2026-03-24 10:15:00 UTC") do
      AgentDeployments::RecordHeartbeat.call(
        deployment: deployment,
        health_status: "healthy",
        health_metadata: { "latency_ms" => 82 },
        auto_resume_eligible: true
      )
    end

    deployment.reload

    assert_equal "active", deployment.bootstrap_state
    assert deployment.healthy?
    assert_equal({ "latency_ms" => 82 }, deployment.health_metadata)
    assert_equal Time.zone.parse("2026-03-24 10:15:00 UTC"), deployment.last_heartbeat_at
    assert_equal Time.zone.parse("2026-03-24 10:15:00 UTC"), deployment.last_health_check_at
    assert deployment.auto_resume_eligible?
  end
end
