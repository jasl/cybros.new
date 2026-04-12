module AgentAPI
  class RegistrationsController < BaseController
    skip_before_action :authenticate_agent_connection!, only: :create

    def create
      registration = AgentDefinitionVersions::Register.call(
        pairing_token: request_payload.fetch("pairing_token"),
        endpoint_metadata: request_payload.fetch("endpoint_metadata", {}),
        definition_package: request_payload.fetch("definition_package")
      )
      capability_contract = RuntimeCapabilityContract.build(
        execution_runtime: registration.execution_runtime,
        agent_definition_version: registration.agent_definition_version
      )

      render json: capability_contract.capability_response(
        method_id: "agent_registration",
        execution_runtime_id: registration.execution_runtime&.public_id,
        execution_runtime_fingerprint: registration.execution_runtime&.execution_runtime_fingerprint
      ).merge(
        agent_id: registration.agent_definition_version.agent.public_id,
        agent_definition_version_id: registration.agent_definition_version.public_id,
        agent_connection_id: registration.agent_connection.public_id,
        agent_connection_credential: registration.agent_connection_credential,
        execution_runtime_version_id: registration.execution_runtime&.current_execution_runtime_version&.public_id,
      ), status: :created
    end
  end
end
