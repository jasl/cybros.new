module ExecutionRuntimeSessions
  class Open
    def self.call(...)
      new(...).call
    end

    def self.payload_for(execution_runtime:, execution_runtime_connection:, method_id:, execution_runtime_connection_credential: nil, reconciliation_report: nil)
      contract = RuntimeCapabilityContract.build(execution_runtime: execution_runtime)

      {
        "method_id" => method_id,
        "execution_runtime_id" => execution_runtime.public_id,
        "execution_runtime_version_id" => execution_runtime.current_execution_runtime_version&.public_id,
        "execution_runtime_connection_id" => execution_runtime_connection.public_id,
        "execution_runtime_connection_credential" => execution_runtime_connection_credential,
        "execution_runtime_fingerprint" => execution_runtime.execution_runtime_fingerprint,
        "execution_runtime_kind" => execution_runtime.kind,
        "execution_runtime_capability_payload" => contract.execution_runtime_capability_payload,
        "execution_runtime_tool_catalog" => contract.execution_runtime_tool_catalog,
        "execution_runtime_plane" => contract.execution_runtime_plane,
        "transport_hints" => transport_hints,
        "runtime_policy" => runtime_policy,
        "reconciliation_report" => reconciliation_report,
      }.compact
    end

    def initialize(onboarding_token:, endpoint_metadata:, version_package:)
      @onboarding_token = onboarding_token
      @endpoint_metadata = endpoint_metadata
      @version_package = version_package
    end

    def call
      registration = ExecutionRuntimeVersions::Register.call(
        onboarding_token: @onboarding_token,
        endpoint_metadata: @endpoint_metadata,
        version_package: @version_package
      )

      self.class.payload_for(
        execution_runtime: registration.execution_runtime,
        execution_runtime_connection: registration.execution_runtime_connection,
        execution_runtime_connection_credential: registration.execution_runtime_connection_credential,
        method_id: "execution_runtime_session_open"
      )
    end

    def self.transport_hints
      {
        "websocket" => {
          "path" => "/cable",
          "channel" => "ControlPlaneChannel",
        },
        "mailbox" => {
          "pull_path" => "/execution_runtime_api/mailbox/pull",
          "default_limit" => AgentControl::Poll::DEFAULT_LIMIT,
        },
        "events" => {
          "batch_path" => "/execution_runtime_api/events/batch",
        },
      }
    end

    def self.runtime_policy
      {
        "websocket_preferred" => true,
        "poll_fallback_enabled" => true,
      }
    end

    private_class_method :transport_hints, :runtime_policy
  end
end
