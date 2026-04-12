module AgentAPI
  class CapabilitiesController < BaseController
    def show
      render json: capability_payload(method_id: "capabilities_refresh")
    end

    def create
      result = AgentDefinitionVersions::Handshake.call(
        agent_connection: current_agent_connection,
        execution_runtime: current_execution_runtime,
        definition_package: request_payload.fetch("definition_package")
      )

      render json: capability_payload(
        method_id: "capabilities_handshake",
        agent_definition_version: result.agent_definition_version,
        reconciliation_report: result.reconciliation_report,
        runtime_capability_contract: result.runtime_capability_contract
      )
    end

    private

    def capability_payload(
      method_id:,
      agent_definition_version: current_agent_definition_version,
      reconciliation_report: nil,
      runtime_capability_contract: nil
    )
      contract = runtime_capability_contract || RuntimeCapabilityContract.build(
        execution_runtime: current_execution_runtime,
        agent_definition_version: agent_definition_version
      )

      contract.capability_response(
        method_id: method_id,
        execution_runtime_id: current_execution_runtime&.public_id,
        execution_runtime_fingerprint: current_execution_runtime&.execution_runtime_fingerprint,
        reconciliation_report: reconciliation_report
      ).merge(
        "agent_definition_version_id" => agent_definition_version.public_id,
        "execution_runtime_version_id" => current_execution_runtime&.current_execution_runtime_version&.public_id,
        "governed_effective_tool_catalog" => ToolBindings::GovernedCatalog.call(
          agent_definition_version: agent_definition_version,
          execution_runtime: current_execution_runtime
        )
      )
    end
  end
end
