module ExecutionRuntimes
  class Reconcile
    MissingExecutionRuntimeFingerprint = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, execution_runtime_fingerprint:, kind:, connection_metadata:)
      @installation = installation
      @execution_runtime_fingerprint = execution_runtime_fingerprint.to_s.strip
      @kind = kind
      @connection_metadata = connection_metadata
    end

    def call
      raise MissingExecutionRuntimeFingerprint, "execution runtime fingerprint must be provided" if @execution_runtime_fingerprint.blank?

      execution_runtime = find_existing_execution_runtime || ExecutionRuntime.new(installation: @installation)
      execution_runtime.update!(
        display_name: execution_runtime.display_name.presence || @execution_runtime_fingerprint,
        kind: @kind,
        lifecycle_state: "active"
      )
      execution_runtime
    end

    def find_existing_execution_runtime
      ExecutionRuntime
        .where(installation: @installation)
        .where(
          active_execution_runtime_version_id: ExecutionRuntimeVersion.where(
            execution_runtime_fingerprint: @execution_runtime_fingerprint
          ).select(:id)
        )
        .order(:id)
        .first
    end
  end
end
