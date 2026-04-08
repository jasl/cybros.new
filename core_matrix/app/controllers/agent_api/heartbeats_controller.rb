module AgentAPI
  class HeartbeatsController < BaseController
    def create
      agent_session = AgentProgramVersions::RecordHeartbeat.call(
        agent_session: current_agent_session,
        deployment: current_deployment,
        health_status: request_payload.fetch("health_status"),
        health_metadata: request_payload.fetch("health_metadata", {}),
        auto_resume_eligible: request_payload.fetch("auto_resume_eligible"),
        unavailability_reason: request_payload["unavailability_reason"]
      )

      render json: {
        method_id: "agent_health",
        agent_program_version_id: current_deployment.public_id,
        agent_session_id: agent_session.public_id,
        health_status: agent_session.health_status,
        health_metadata: agent_session.health_metadata,
        auto_resume_eligible: agent_session.auto_resume_eligible,
        lifecycle_state: agent_session.lifecycle_state,
        last_heartbeat_at: agent_session.last_heartbeat_at&.iso8601,
      }
    end
  end
end
