module AgentAPI
  class HealthController < BaseController
    def show
      render json: {
        method_id: "agent_health",
        agent_id: current_agent_snapshot.agent.public_id,
        agent_snapshot_id: current_agent_snapshot.public_id,
        agent_connection_id: current_agent_connection.public_id,
        execution_runtime_id: current_execution_runtime&.public_id,
        execution_runtime_fingerprint: current_execution_runtime&.execution_runtime_fingerprint,
        fingerprint: current_agent_snapshot.fingerprint,
        health_status: current_agent_connection.health_status,
        health_metadata: current_agent_connection.health_metadata,
        auto_resume_eligible: current_agent_connection.auto_resume_eligible,
        lifecycle_state: current_agent_connection.lifecycle_state,
        protocol_version: current_agent_snapshot.protocol_version,
        sdk_version: current_agent_snapshot.sdk_version,
        last_heartbeat_at: current_agent_connection.last_heartbeat_at&.iso8601,
      }.compact
    end
  end
end
