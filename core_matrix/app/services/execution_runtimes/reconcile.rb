module ExecutionRuntimes
  class Reconcile
    MissingRuntimeFingerprint = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, runtime_fingerprint:, kind:, connection_metadata:)
      @installation = installation
      @runtime_fingerprint = runtime_fingerprint.to_s.strip
      @kind = kind
      @connection_metadata = connection_metadata
    end

    def call
      raise MissingRuntimeFingerprint, "runtime fingerprint must be provided" if @runtime_fingerprint.blank?

      execution_runtime = ExecutionRuntime.find_or_initialize_by(
        installation: @installation,
        runtime_fingerprint: @runtime_fingerprint
      )
      execution_runtime.update!(
        display_name: execution_runtime.display_name.presence || @runtime_fingerprint,
        kind: @kind,
        connection_metadata: @connection_metadata,
        lifecycle_state: "active"
      )
      execution_runtime
    end
  end
end
