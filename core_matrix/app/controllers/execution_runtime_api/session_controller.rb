module ExecutionRuntimeAPI
  class SessionController < BaseController
    skip_before_action :authenticate_execution_runtime_connection!, only: :open

    def open
      render json: ExecutionRuntimeSessions::Open.call(
        onboarding_token: request_payload.fetch("onboarding_token"),
        endpoint_metadata: request_payload.fetch("endpoint_metadata", {}),
        version_package: request_payload.fetch("version_package")
      ), status: :created
    end

    def refresh
      render json: ExecutionRuntimeSessions::Refresh.call(
        execution_runtime_connection: current_execution_runtime_connection,
        version_package: request_payload["version_package"]
      )
    end
  end
end
