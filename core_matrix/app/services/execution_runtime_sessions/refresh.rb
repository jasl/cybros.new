module ExecutionRuntimeSessions
  class Refresh
    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime_connection:, version_package: nil, occurred_at: Time.current)
      @execution_runtime_connection = execution_runtime_connection
      @execution_runtime = execution_runtime_connection.execution_runtime
      @version_package = version_package
      @occurred_at = occurred_at
    end

    def call
      refresh_result =
        if @version_package.present?
          ExecutionRuntimeVersions::Refresh.call(
            execution_runtime_connection: @execution_runtime_connection,
            version_package: @version_package
          )
        else
          ExecutionRuntimeVersions::Refresh::Result.new(
            execution_runtime: @execution_runtime,
            execution_runtime_version: @execution_runtime.current_execution_runtime_version,
            reconciliation_report: { "runtime_version_changed" => false }
          )
        end

      @execution_runtime_connection.update!(last_heartbeat_at: @occurred_at)

      ExecutionRuntimeSessions::Open.payload_for(
        execution_runtime: refresh_result.execution_runtime,
        execution_runtime_connection: @execution_runtime_connection,
        method_id: "execution_runtime_session_refresh",
        reconciliation_report: refresh_result.reconciliation_report
      )
    end
  end
end
