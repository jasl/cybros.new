module AgentAPI
  class HealthController < BaseController
    def show
      render json: {
        method_id: "agent_health",
        agent_id: current_agent_definition_version.agent.public_id,
        agent_definition_version_id: current_agent_definition_version.public_id,
        agent_connection_id: current_agent_connection.public_id,
        execution_runtime_id: current_execution_runtime&.public_id,
        execution_runtime_version_id: current_execution_runtime&.current_execution_runtime_version&.public_id,
        execution_runtime_fingerprint: current_execution_runtime&.execution_runtime_fingerprint,
        agent_definition_fingerprint: current_agent_definition_version.definition_fingerprint,
        health_status: current_agent_connection.health_status,
        health_metadata: current_agent_connection.health_metadata,
        auto_resume_eligible: current_agent_connection.auto_resume_eligible,
        lifecycle_state: current_agent_connection.lifecycle_state,
        protocol_version: current_agent_definition_version.protocol_version,
        sdk_version: current_agent_definition_version.sdk_version,
        last_heartbeat_at: current_agent_connection.last_heartbeat_at&.iso8601,
      }.compact
    end
  end
end
