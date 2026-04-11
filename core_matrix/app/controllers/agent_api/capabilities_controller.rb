module AgentAPI
  class CapabilitiesController < BaseController
    def show
      render json: capability_payload(method_id: "capabilities_refresh")
    end

    def create
      result = AgentSnapshots::Handshake.call(
        agent_connection: current_agent_connection,
        agent_snapshot: current_agent_snapshot,
        execution_runtime: current_execution_runtime,
        fingerprint: request_payload.fetch("fingerprint"),
        protocol_version: request_payload.fetch("protocol_version"),
        sdk_version: request_payload.fetch("sdk_version"),
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
        agent_snapshot: current_agent_snapshot
      )

      contract.capability_response(
        method_id: method_id,
        execution_runtime_id: current_execution_runtime&.public_id,
        execution_runtime_fingerprint: current_execution_runtime&.execution_runtime_fingerprint,
        reconciliation_report: reconciliation_report
      ).merge(
        "governed_effective_tool_catalog" => ToolBindings::GovernedCatalog.call(
          agent_snapshot: current_agent_snapshot,
          execution_runtime: current_execution_runtime
        )
      )
    end
  end
end
