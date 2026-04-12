module ExecutionRuntimeVersions
  class Refresh
    Result = Struct.new(
      :execution_runtime,
      :execution_runtime_version,
      :reconciliation_report,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime_connection:, version_package:)
      @execution_runtime_connection = execution_runtime_connection
      @execution_runtime = execution_runtime_connection.execution_runtime
      @version_package = version_package
    end

    def call
      current_runtime_version = @execution_runtime_connection.execution_runtime_version
      upsert_result = UpsertFromPackage.call(
        execution_runtime: @execution_runtime,
        version_package: @version_package
      )
      execution_runtime_version = upsert_result.execution_runtime_version

      @execution_runtime.update!(
        kind: execution_runtime_version.kind,
        display_name: execution_runtime_version.reflected_host_metadata["display_name"].presence || @execution_runtime.display_name,
        published_execution_runtime_version: execution_runtime_version,
        lifecycle_state: "active"
      )
      @execution_runtime_connection.update!(execution_runtime_version: execution_runtime_version)

      Result.new(
        execution_runtime: @execution_runtime,
        execution_runtime_version: execution_runtime_version,
        reconciliation_report: {
          "runtime_version_changed" => current_runtime_version.id != execution_runtime_version.id,
        }
      )
    end
  end
end
