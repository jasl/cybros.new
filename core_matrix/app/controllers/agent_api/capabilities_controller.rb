module AgentAPI
  class CapabilitiesController < BaseController
    def show
      render json: capability_payload(method_id: "capabilities_refresh")
    end

    def create
      result = AgentDeployments::Handshake.call(
        deployment: current_deployment,
        fingerprint: request_payload.fetch("fingerprint"),
        protocol_version: request_payload.fetch("protocol_version"),
        sdk_version: request_payload.fetch("sdk_version"),
        environment_capability_payload: request_payload["environment_capability_payload"],
        environment_tool_catalog: request_payload["environment_tool_catalog"],
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
        capability_snapshot: result.capability_snapshot,
        runtime_capability_contract: result.runtime_capability_contract
      )
    end

    private

    def capability_payload(
      method_id:,
      reconciliation_report: nil,
      capability_snapshot: current_deployment.active_capability_snapshot,
      runtime_capability_contract: nil
    )
      execution_environment = current_deployment.reload.execution_environment
      contract = runtime_capability_contract || RuntimeCapabilityContract.build(
        execution_environment: execution_environment,
        capability_snapshot: capability_snapshot
      )

      contract.capability_response(
        method_id: method_id,
        execution_environment_id: execution_environment.public_id,
        environment_fingerprint: execution_environment.environment_fingerprint,
        reconciliation_report: reconciliation_report
      )
    end
  end
end
