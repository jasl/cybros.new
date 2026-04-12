module ExecutionRuntimeAPI
  class CapabilitiesController < BaseController
    def show
      render json: capability_payload(method_id: "capabilities_refresh")
    end

    def create
      result = ExecutionRuntimeVersions::Refresh.call(
        execution_runtime_connection: current_execution_runtime_connection,
        version_package: request_payload.fetch("version_package")
      )

      render json: capability_payload(
        method_id: "capabilities_handshake",
        execution_runtime: result.execution_runtime
      )
    end

    private

    def capability_payload(method_id:, execution_runtime: current_execution_runtime)
      contract = RuntimeCapabilityContract.build(execution_runtime: execution_runtime)

      {
        method_id: method_id,
        execution_runtime_id: execution_runtime.public_id,
        execution_runtime_version_id: execution_runtime.current_execution_runtime_version&.public_id,
        execution_runtime_fingerprint: execution_runtime.execution_runtime_fingerprint,
        execution_runtime_kind: execution_runtime.kind,
        execution_runtime_capability_payload: contract.execution_runtime_capability_payload,
        execution_runtime_tool_catalog: contract.execution_runtime_tool_catalog,
        execution_runtime_plane: contract.execution_runtime_plane,
      }
    end
  end
end
