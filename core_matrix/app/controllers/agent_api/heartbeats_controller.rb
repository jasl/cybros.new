module AgentAPI
  class HeartbeatsController < BaseController
    def create
      deployment = AgentDeployments::RecordHeartbeat.call(
        deployment: current_deployment,
        health_status: request_payload.fetch("health_status"),
        health_metadata: request_payload.fetch("health_metadata", {}),
        auto_resume_eligible: request_payload.fetch("auto_resume_eligible"),
        unavailability_reason: request_payload["unavailability_reason"]
      )

      render json: {
        method_id: "agent_health",
        deployment_id: deployment.public_id,
        health_status: deployment.health_status,
        bootstrap_state: deployment.bootstrap_state,
        last_heartbeat_at: deployment.last_heartbeat_at&.iso8601,
      }
    end
  end
end
