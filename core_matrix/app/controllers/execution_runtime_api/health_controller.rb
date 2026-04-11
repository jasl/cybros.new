module ExecutionRuntimeAPI
  class HealthController < BaseController
    def show
      render json: {
        method_id: "execution_runtime_health",
        execution_runtime_id: current_execution_runtime.public_id,
        execution_runtime_connection_id: current_execution_runtime_connection.public_id,
        execution_runtime_fingerprint: current_execution_runtime.execution_runtime_fingerprint,
        execution_runtime_kind: current_execution_runtime.kind,
        lifecycle_state: current_execution_runtime_connection.lifecycle_state,
        last_heartbeat_at: current_execution_runtime_connection.last_heartbeat_at&.iso8601,
      }
    end
  end
end
