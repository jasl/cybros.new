module ManualAcceptanceSupport
  class RuntimeRegistration
    FETCHABLE_KEYS = {
      manifest: :manifest,
      registration: :registration,
      heartbeat: :heartbeat,
      machine_credential: :machine_credential,
      executor_machine_credential: :executor_machine_credential,
      agent_program_version: :agent_program_version,
      executor_program: :executor_program,
      deployment: :deployment,
      runtime: :runtime,
      agent_program: :agent_program,
      agent_session: :agent_session,
      executor_session: :executor_session,
    }.freeze

    attr_reader :manifest,
      :registration,
      :heartbeat,
      :machine_credential,
      :executor_machine_credential,
      :agent_program_version,
      :executor_program,
      :runtime

    def initialize(
      manifest:,
      machine_credential:,
      executor_machine_credential: nil,
      agent_program_version:,
      executor_program: nil,
      runtime: nil,
      registration: nil,
      heartbeat: nil
    )
      @manifest = manifest
      @registration = registration
      @heartbeat = heartbeat
      @machine_credential = machine_credential
      @executor_machine_credential = executor_machine_credential.presence || machine_credential
      @agent_program_version = agent_program_version
      @executor_program = executor_program
      @runtime = runtime
    end

    def deployment
      runtime&.deployment || agent_program_version
    end

    def agent_program
      runtime&.agent_program || agent_program_version.try(:agent_program)
    end

    def agent_session
      runtime&.agent_session
    end

    def executor_session
      runtime&.executor_session
    end

    def fetch(key)
      method_name = FETCHABLE_KEYS[key.to_sym]
      raise KeyError, "key not found: #{key}" if method_name.blank?

      public_send(method_name)
    end

    def to_h
      FETCHABLE_KEYS.keys.index_with { |key| fetch(key) }
    end
  end
end
