module ExecutionRuntimeAPI
  class CapabilitiesController < BaseController
    def show
      render json: capability_payload(method_id: "capabilities_refresh")
    end

    def create
      execution_runtime = ExecutionRuntimes::RecordCapabilities.call(
        execution_runtime: current_execution_runtime,
        capability_payload: request_payload.fetch("execution_runtime_capability_payload", current_execution_runtime.capability_payload),
        tool_catalog: request_payload.fetch("execution_runtime_tool_catalog", current_execution_runtime.tool_catalog)
      )

      render json: capability_payload(
        method_id: "capabilities_handshake",
        execution_runtime: execution_runtime
      )
    end

    private

    def capability_payload(method_id:, execution_runtime: current_execution_runtime)
      contract = RuntimeCapabilityContract.build(execution_runtime: execution_runtime)

      {
        method_id: method_id,
        execution_runtime_id: execution_runtime.public_id,
        execution_runtime_fingerprint: execution_runtime.execution_runtime_fingerprint,
        execution_runtime_kind: execution_runtime.kind,
        execution_runtime_capability_payload: contract.execution_runtime_capability_payload,
        execution_runtime_tool_catalog: contract.execution_runtime_tool_catalog,
        execution_runtime_plane: contract.execution_runtime_plane,
      }
    end
  end
end
