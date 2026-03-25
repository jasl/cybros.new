module AgentAPI
  class RegistrationsController < BaseController
    skip_before_action :authenticate_deployment!, only: :create

    def create
      registration = AgentDeployments::Register.call(
        enrollment_token: request_payload.fetch("enrollment_token"),
        execution_environment: ExecutionEnvironment.find_by_public_id!(request_payload.fetch("execution_environment_id")),
        fingerprint: request_payload.fetch("fingerprint"),
        endpoint_metadata: request_payload.fetch("endpoint_metadata", {}),
        protocol_version: request_payload.fetch("protocol_version"),
        sdk_version: request_payload.fetch("sdk_version"),
        protocol_methods: request_payload.fetch("protocol_methods", []),
        tool_catalog: request_payload.fetch("tool_catalog", []),
        config_schema_snapshot: request_payload.fetch("config_schema_snapshot", {}),
        conversation_override_schema_snapshot: request_payload.fetch("conversation_override_schema_snapshot", {}),
        default_config_snapshot: request_payload.fetch("default_config_snapshot", {})
      )

      render json: {
        deployment_id: registration.deployment.public_id,
        agent_installation_id: registration.deployment.agent_installation.public_id,
        fingerprint: registration.deployment.fingerprint,
        bootstrap_state: registration.deployment.bootstrap_state,
        machine_credential: registration.machine_credential,
        capability_snapshot: registration.capability_snapshot.as_contract_payload,
      }, status: :created
    end
  end
end
