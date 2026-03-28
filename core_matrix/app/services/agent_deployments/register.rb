module AgentDeployments
  class Register
    InvalidEnrollment = Class.new(StandardError)
    ExpiredEnrollment = Class.new(StandardError)

    Result = Struct.new(:enrollment, :execution_environment, :deployment, :capability_snapshot, :machine_credential, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(enrollment_token:, environment_fingerprint:, environment_kind:, environment_connection_metadata:, environment_capability_payload:, environment_tool_catalog:, fingerprint:, endpoint_metadata:, protocol_version:, sdk_version:, protocol_methods:, tool_catalog:, profile_catalog:, config_schema_snapshot:, conversation_override_schema_snapshot:, default_config_snapshot:)
      @enrollment_token = enrollment_token
      @environment_fingerprint = environment_fingerprint
      @environment_kind = environment_kind
      @environment_connection_metadata = environment_connection_metadata
      @environment_capability_payload = environment_capability_payload
      @environment_tool_catalog = environment_tool_catalog
      @fingerprint = fingerprint
      @endpoint_metadata = endpoint_metadata
      @protocol_version = protocol_version
      @sdk_version = sdk_version
      @protocol_methods = protocol_methods
      @tool_catalog = tool_catalog
      @profile_catalog = profile_catalog
      @config_schema_snapshot = config_schema_snapshot
      @conversation_override_schema_snapshot = conversation_override_schema_snapshot
      @default_config_snapshot = default_config_snapshot
    end

    def call
      enrollment = AgentEnrollment.find_by_plaintext_token(@enrollment_token)
      raise InvalidEnrollment, "enrollment token is invalid" if enrollment.blank? || enrollment.consumed?
      raise ExpiredEnrollment, "enrollment token has expired" if enrollment.expired?

      ApplicationRecord.transaction do
        execution_environment = ExecutionEnvironments::Reconcile.call(
          installation: enrollment.installation,
          environment_fingerprint: @environment_fingerprint,
          kind: @environment_kind,
          connection_metadata: @environment_connection_metadata
        )
        ExecutionEnvironments::RecordCapabilities.call(
          execution_environment: execution_environment,
          capability_payload: @environment_capability_payload,
          tool_catalog: @environment_tool_catalog
        )
        runtime_capability_contract = RuntimeCapabilityContract.build(
          execution_environment: execution_environment,
          environment_capability_payload: @environment_capability_payload,
          environment_tool_catalog: @environment_tool_catalog,
          protocol_methods: @protocol_methods,
          tool_catalog: @tool_catalog,
          profile_catalog: @profile_catalog,
          config_schema_snapshot: @config_schema_snapshot,
          conversation_override_schema_snapshot: @conversation_override_schema_snapshot,
          default_config_snapshot: @default_config_snapshot
        )
        machine_credential, machine_credential_digest = AgentDeployment.issue_machine_credential
        deployment = AgentDeployment.create!(
          installation: enrollment.installation,
          agent_installation: enrollment.agent_installation,
          execution_environment: execution_environment,
          fingerprint: @fingerprint,
          endpoint_metadata: @endpoint_metadata,
          protocol_version: @protocol_version,
          sdk_version: @sdk_version,
          machine_credential_digest: machine_credential_digest,
          health_status: "offline",
          health_metadata: {},
          bootstrap_state: "pending"
        )
        capability_snapshot = CapabilitySnapshots::Reconcile.call(
          deployment: deployment,
          runtime_capability_contract: runtime_capability_contract
        )
        deployment.instance_variable_set(:@plaintext_machine_credential, machine_credential)
        enrollment.consume!

        AuditLog.record!(
          installation: enrollment.installation,
          action: "agent_deployment.registered",
          subject: deployment,
          metadata: {
            "agent_enrollment_id" => enrollment.id,
            "agent_installation_id" => enrollment.agent_installation_id,
            "execution_environment_id" => execution_environment.id,
          }
        )

        Result.new(
          enrollment: enrollment,
          execution_environment: execution_environment,
          deployment: deployment,
          capability_snapshot: capability_snapshot,
          machine_credential: machine_credential
        )
      end
    end
  end
end
