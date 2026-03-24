module AgentAPI
  class CapabilitiesController < BaseController
    def show
      render json: current_deployment.active_capability_snapshot.as_contract_payload(method_id: "capabilities_refresh")
    end

    def create
      result = AgentDeployments::Handshake.call(
        deployment: current_deployment,
        fingerprint: request_payload.fetch("fingerprint"),
        protocol_version: request_payload.fetch("protocol_version"),
        sdk_version: request_payload.fetch("sdk_version"),
        protocol_methods: request_payload.fetch("protocol_methods", []),
        tool_catalog: request_payload.fetch("tool_catalog", []),
        config_schema_snapshot: request_payload.fetch("config_schema_snapshot", {}),
        conversation_override_schema_snapshot: request_payload.fetch("conversation_override_schema_snapshot", {}),
        default_config_snapshot: request_payload.fetch("default_config_snapshot", {})
      )

      render json: result.capability_snapshot.as_contract_payload(
        method_id: "capabilities_handshake",
        reconciliation_report: result.reconciliation_report
      )
    end
  end
end
