module AgentAPI
  class RegistrationsController < BaseController
    skip_before_action :authenticate_agent_session!, only: :create

    def create
      registration = AgentProgramVersions::Register.call(
        enrollment_token: request_payload.fetch("enrollment_token"),
        executor_fingerprint: request_payload["executor_fingerprint"],
        executor_kind: request_payload.fetch("executor_kind", "local"),
        executor_connection_metadata: request_payload["executor_connection_metadata"],
        executor_capability_payload: request_payload["executor_capability_payload"],
        executor_tool_catalog: request_payload["executor_tool_catalog"],
        fingerprint: request_payload.fetch("fingerprint"),
        endpoint_metadata: request_payload.fetch("endpoint_metadata", {}),
        protocol_version: request_payload.fetch("protocol_version"),
        sdk_version: request_payload.fetch("sdk_version"),
        protocol_methods: request_payload.fetch("protocol_methods", []),
        tool_catalog: request_payload.fetch("tool_catalog", []),
        profile_catalog: request_payload.fetch("profile_catalog", {}),
        config_schema_snapshot: request_payload.fetch("config_schema_snapshot", {}),
        conversation_override_schema_snapshot: request_payload.fetch("conversation_override_schema_snapshot", {}),
        default_config_snapshot: request_payload.fetch("default_config_snapshot", {})
      )
      capability_contract = RuntimeCapabilityContract.build(
        executor_program: registration.executor_program,
        agent_program_version: registration.deployment
      )

      render json: capability_contract.capability_response(
        method_id: "program_registration",
        executor_program_id: registration.executor_program&.public_id,
        executor_fingerprint: registration.executor_program&.executor_fingerprint
      ).merge(
        agent_program_id: registration.deployment.agent_program.public_id,
        agent_program_version_id: registration.deployment.public_id,
        agent_session_id: registration.agent_session.public_id,
        executor_session_id: registration.executor_session&.public_id,
        machine_credential: registration.session_credential,
        session_credential: registration.session_credential,
        executor_machine_credential: registration.executor_session_credential,
        executor_session_credential: registration.executor_session_credential,
      ), status: :created
    end
  end
end
