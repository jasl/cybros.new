module ProgramAPI
  class RegistrationsController < BaseController
    skip_before_action :authenticate_agent_session!, only: :create

    def create
      registration = AgentProgramVersions::Register.call(
        enrollment_token: request_payload.fetch("enrollment_token"),
        runtime_fingerprint: request_payload["runtime_fingerprint"],
        runtime_kind: request_payload.fetch("runtime_kind", "local"),
        runtime_connection_metadata: request_payload["runtime_connection_metadata"],
        execution_capability_payload: request_payload["execution_capability_payload"],
        execution_tool_catalog: request_payload["execution_tool_catalog"],
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
        execution_runtime: registration.execution_runtime,
        agent_program_version: registration.deployment
      )

      render json: capability_contract.capability_response(
        method_id: "program_registration",
        execution_runtime_id: registration.execution_runtime&.public_id,
        runtime_fingerprint: registration.execution_runtime&.runtime_fingerprint
      ).merge(
        agent_program_id: registration.deployment.agent_program.public_id,
        agent_program_version_id: registration.deployment.public_id,
        agent_session_id: registration.agent_session.public_id,
        execution_session_id: registration.execution_session&.public_id,
        machine_credential: registration.session_credential,
        session_credential: registration.session_credential,
        execution_machine_credential: registration.execution_session_credential,
        execution_session_credential: registration.execution_session_credential,
      ), status: :created
    end
  end
end
