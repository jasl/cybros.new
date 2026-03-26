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

  test "healthy heartbeat on a pending replacement deployment supersedes the previous active deployment" do
    installation = create_installation!
    agent_installation = create_agent_installation!(installation: installation)
    active_environment = create_execution_environment!(installation: installation)
    previous = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: active_environment,
      bootstrap_state: "active",
      health_status: "healthy"
    )
    replacement_environment = create_execution_environment!(installation: installation)
    replacement = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: replacement_environment,
      bootstrap_state: "pending",
      health_status: "offline"
    )

    AgentDeployments::RecordHeartbeat.call(
      deployment: replacement,
      health_status: "healthy",
      health_metadata: { "source" => "external-fenix" },
      auto_resume_eligible: true
    )

    assert_equal "active", replacement.reload.bootstrap_state
    assert_equal "superseded", previous.reload.bootstrap_state
  end
end
