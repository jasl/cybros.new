require "test_helper"

class AgentDeploymentTest < ActiveSupport::TestCase
  test "enforces one active deployment per agent installation and tracks health" do
    installation = create_installation!
    agent_installation = create_agent_installation!(installation: installation)
    environment = create_execution_environment!(installation: installation)

    deployment = create_agent_deployment!(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: environment,
      bootstrap_state: "active",
      health_status: "healthy"
    )

    assert deployment.healthy?
    assert deployment.active?

    conflicting = AgentDeployment.new(
      installation: installation,
      agent_installation: agent_installation,
      execution_environment: environment,
      fingerprint: "fp-conflict",
      endpoint_metadata: {},
      protocol_version: "2026-03-24",
      sdk_version: "fenix-0.1.0",
      machine_credential_digest: Digest::SHA256.hexdigest("machine-conflict"),
      health_status: "degraded",
      health_metadata: {},
      bootstrap_state: "active"
    )

    assert_not conflicting.valid?
    assert_includes conflicting.errors[:agent_installation_id], "already has an active deployment"
  end
end
