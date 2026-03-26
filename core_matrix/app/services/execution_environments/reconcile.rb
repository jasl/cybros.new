module ExecutionEnvironments
  class Reconcile
    MissingEnvironmentFingerprint = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, environment_fingerprint:, kind:, connection_metadata:)
      @installation = installation
      @environment_fingerprint = environment_fingerprint.to_s.strip
      @kind = kind
      @connection_metadata = connection_metadata
    end

    def call
      raise MissingEnvironmentFingerprint, "environment fingerprint must be provided" if @environment_fingerprint.blank?

      execution_environment = ExecutionEnvironment.find_or_initialize_by(
        installation: @installation,
        environment_fingerprint: @environment_fingerprint
      )
      execution_environment.update!(
        kind: @kind,
        connection_metadata: @connection_metadata,
        lifecycle_state: "active"
      )
      execution_environment
    end
  end
end
