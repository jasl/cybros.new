module ExecutionRuntimeAPI
  class RegistrationsController < BaseController
    skip_before_action :authenticate_execution_runtime_connection!, only: :create

    def create
      registration = ExecutionRuntimeVersions::Register.call(
        onboarding_token: request_payload.fetch("onboarding_token"),
        endpoint_metadata: request_payload.fetch("endpoint_metadata", {}),
        version_package: request_payload.fetch("version_package")
      )

      render json: capability_payload(
        method_id: "execution_runtime_registration",
        execution_runtime: registration.execution_runtime
      ).merge(
        execution_runtime_version_id: registration.execution_runtime_version.public_id,
        execution_runtime_connection_id: registration.execution_runtime_connection.public_id,
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential
      ), status: :created
    end

    private

    def capability_payload(method_id:, execution_runtime:)
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
