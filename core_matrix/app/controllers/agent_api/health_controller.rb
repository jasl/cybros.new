module AgentAPI
  class HealthController < BaseController
    def show
      render json: {
        method_id: "agent_health",
        deployment_id: current_deployment.id,
        fingerprint: current_deployment.fingerprint,
        health_status: current_deployment.health_status,
        bootstrap_state: current_deployment.bootstrap_state,
        protocol_version: current_deployment.protocol_version,
        sdk_version: current_deployment.sdk_version,
        agent_capabilities_version: current_deployment.capability_snapshot_version,
        last_heartbeat_at: current_deployment.last_heartbeat_at&.iso8601,
      }
    end
  end
end
