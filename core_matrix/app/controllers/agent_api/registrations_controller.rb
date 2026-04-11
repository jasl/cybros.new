module AgentAPI
  class RegistrationsController < BaseController
    skip_before_action :authenticate_agent_connection!, only: :create

    def create
      registration = AgentSnapshots::Register.call(
        enrollment_token: request_payload.fetch("enrollment_token"),
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
        agent_snapshot: registration.agent_snapshot
      )

      render json: capability_contract.capability_response(
        method_id: "agent_registration",
        execution_runtime_id: registration.execution_runtime&.public_id,
        execution_runtime_fingerprint: registration.execution_runtime&.execution_runtime_fingerprint
      ).merge(
        agent_id: registration.agent_snapshot.agent.public_id,
        agent_snapshot_id: registration.agent_snapshot.public_id,
        agent_connection_id: registration.agent_connection.public_id,
        agent_connection_credential: registration.agent_connection_credential,
      ), status: :created
    end
  end
end
