module AgentAPI
  class HeartbeatsController < BaseController
    def create
      agent_connection = AgentSnapshots::RecordHeartbeat.call(
        agent_connection: current_agent_connection,
        agent_snapshot: current_agent_snapshot,
        health_status: request_payload.fetch("health_status"),
        health_metadata: request_payload.fetch("health_metadata", {}),
        auto_resume_eligible: request_payload.fetch("auto_resume_eligible"),
        unavailability_reason: request_payload["unavailability_reason"]
      )

      render json: {
        method_id: "agent_health",
        agent_snapshot_id: current_agent_snapshot.public_id,
        agent_connection_id: agent_connection.public_id,
        health_status: agent_connection.health_status,
        health_metadata: agent_connection.health_metadata,
        auto_resume_eligible: agent_connection.auto_resume_eligible,
        lifecycle_state: agent_connection.lifecycle_state,
        last_heartbeat_at: agent_connection.last_heartbeat_at&.iso8601,
      }
    end
  end
end
