module AgentDeployments
  class Register
    InvalidEnrollment = Class.new(StandardError)
    ExpiredEnrollment = Class.new(StandardError)
    ExecutionEnvironmentMismatch = Class.new(StandardError)

    Result = Struct.new(:enrollment, :deployment, :capability_snapshot, :machine_credential, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(enrollment_token:, execution_environment:, fingerprint:, endpoint_metadata:, protocol_version:, sdk_version:, protocol_methods:, tool_catalog:, config_schema_snapshot:, conversation_override_schema_snapshot:, default_config_snapshot:)
      @enrollment_token = enrollment_token
      @execution_environment = execution_environment
      @fingerprint = fingerprint
      @endpoint_metadata = endpoint_metadata
      @protocol_version = protocol_version
      @sdk_version = sdk_version
      @protocol_methods = protocol_methods
      @tool_catalog = tool_catalog
      @config_schema_snapshot = config_schema_snapshot
      @conversation_override_schema_snapshot = conversation_override_schema_snapshot
      @default_config_snapshot = default_config_snapshot
    end

    def call
      enrollment = AgentEnrollment.find_by_plaintext_token(@enrollment_token)
      raise InvalidEnrollment, "enrollment token is invalid" if enrollment.blank? || enrollment.consumed?
      raise ExpiredEnrollment, "enrollment token has expired" if enrollment.expired?
      validate_execution_environment!(enrollment)

      ApplicationRecord.transaction do
        machine_credential, machine_credential_digest = AgentDeployment.issue_machine_credential
        deployment = AgentDeployment.create!(
          installation: enrollment.installation,
          agent_installation: enrollment.agent_installation,
          execution_environment: @execution_environment,
          fingerprint: @fingerprint,
          endpoint_metadata: @endpoint_metadata,
          protocol_version: @protocol_version,
          sdk_version: @sdk_version,
          machine_credential_digest: machine_credential_digest,
          health_status: "offline",
          health_metadata: {},
          bootstrap_state: "pending"
        )
        capability_snapshot = CapabilitySnapshot.create!(
          agent_deployment: deployment,
          version: 1,
          protocol_methods: @protocol_methods,
          tool_catalog: @tool_catalog,
          config_schema_snapshot: @config_schema_snapshot,
          conversation_override_schema_snapshot: @conversation_override_schema_snapshot,
          default_config_snapshot: @default_config_snapshot
        )
        deployment.update!(active_capability_snapshot: capability_snapshot)
        deployment.instance_variable_set(:@plaintext_machine_credential, machine_credential)
        enrollment.consume!

        AuditLog.record!(
          installation: enrollment.installation,
          action: "agent_deployment.registered",
          subject: deployment,
          metadata: {
            "agent_enrollment_id" => enrollment.id,
            "agent_installation_id" => enrollment.agent_installation_id,
            "execution_environment_id" => @execution_environment.id,
          }
        )

        Result.new(
          enrollment: enrollment,
          deployment: deployment,
          capability_snapshot: capability_snapshot,
          machine_credential: machine_credential
        )
      end
    end

    private

    def validate_execution_environment!(enrollment)
      return if @execution_environment.installation_id == enrollment.installation_id

      raise ExecutionEnvironmentMismatch, "execution environment must belong to the same installation"
    end
  end
end
