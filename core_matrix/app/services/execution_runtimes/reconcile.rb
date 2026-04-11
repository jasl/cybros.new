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

      execution_runtime = ExecutionRuntime.find_or_initialize_by(
        installation: @installation,
        execution_runtime_fingerprint: @execution_runtime_fingerprint
      )
      execution_runtime.update!(
        display_name: execution_runtime.display_name.presence || @execution_runtime_fingerprint,
        kind: @kind,
        connection_metadata: @connection_metadata,
        lifecycle_state: "active"
      )
      execution_runtime
    end
  end
end
