module ExecutorPrograms
  class Reconcile
    MissingExecutorFingerprint = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, executor_fingerprint:, kind:, connection_metadata:)
      @installation = installation
      @executor_fingerprint = executor_fingerprint.to_s.strip
      @kind = kind
      @connection_metadata = connection_metadata
    end

    def call
      raise MissingExecutorFingerprint, "executor fingerprint must be provided" if @executor_fingerprint.blank?

      executor_program = ExecutorProgram.find_or_initialize_by(
        installation: @installation,
        executor_fingerprint: @executor_fingerprint
      )
      executor_program.update!(
        display_name: executor_program.display_name.presence || @executor_fingerprint,
        kind: @kind,
        connection_metadata: @connection_metadata,
        lifecycle_state: "active"
      )
      executor_program
    end
  end
end
