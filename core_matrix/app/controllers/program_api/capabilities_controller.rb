module ProgramAPI
  class CapabilitiesController < BaseController
    def show
      render json: capability_payload(method_id: "capabilities_refresh")
    end

    def create
      result = AgentProgramVersions::Handshake.call(
        agent_session: current_agent_session,
        deployment: current_deployment,
        execution_runtime: current_execution_runtime,
        fingerprint: request_payload.fetch("fingerprint"),
        protocol_version: request_payload.fetch("protocol_version"),
        sdk_version: request_payload.fetch("sdk_version"),
        execution_capability_payload: request_payload["execution_capability_payload"],
        execution_tool_catalog: request_payload["execution_tool_catalog"],
        protocol_methods: request_payload.fetch("protocol_methods", []),
        tool_catalog: request_payload.fetch("tool_catalog", []),
        profile_catalog: request_payload.fetch("profile_catalog", {}),
        config_schema_snapshot: request_payload.fetch("config_schema_snapshot", {}),
        conversation_override_schema_snapshot: request_payload.fetch("conversation_override_schema_snapshot", {}),
        default_config_snapshot: request_payload.fetch("default_config_snapshot", {})
      )

      render json: capability_payload(
        method_id: "capabilities_handshake",
        reconciliation_report: result.reconciliation_report,
        runtime_capability_contract: result.runtime_capability_contract
      )
    end

    private

    def capability_payload(
      method_id:,
      reconciliation_report: nil,
      runtime_capability_contract: nil
    )
      contract = runtime_capability_contract || RuntimeCapabilityContract.build(
        execution_runtime: current_execution_runtime,
        agent_program_version: current_deployment
      )

      contract.capability_response(
        method_id: method_id,
        execution_runtime_id: current_execution_runtime&.public_id,
        runtime_fingerprint: current_execution_runtime&.runtime_fingerprint,
        reconciliation_report: reconciliation_report
      ).merge(
        "governed_effective_tool_catalog" => ToolBindings::GovernedCatalog.call(
          agent_program_version: current_deployment,
          execution_runtime: current_execution_runtime
        )
      )
    end
  end
end
