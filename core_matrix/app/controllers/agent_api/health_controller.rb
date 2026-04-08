module AgentAPI
  class HealthController < BaseController
    def show
      render json: {
        method_id: "agent_health",
        agent_program_id: current_deployment.agent_program.public_id,
        agent_program_version_id: current_deployment.public_id,
        agent_session_id: current_agent_session.public_id,
        executor_program_id: current_executor_program&.public_id,
        executor_fingerprint: current_executor_program&.executor_fingerprint,
        fingerprint: current_deployment.fingerprint,
        health_status: current_agent_session.health_status,
        health_metadata: current_agent_session.health_metadata,
        auto_resume_eligible: current_agent_session.auto_resume_eligible,
        lifecycle_state: current_agent_session.lifecycle_state,
        protocol_version: current_deployment.protocol_version,
        sdk_version: current_deployment.sdk_version,
        last_heartbeat_at: current_agent_session.last_heartbeat_at&.iso8601,
      }.compact
    end
  end
end
