module Runtime
  module Manifest
    class PairingManifest
      PROTOCOL_METHOD_IDS = %w[
        agent_health
        capabilities_handshake
        capabilities_refresh
        execution_started
        execution_progress
        execution_complete
        execution_fail
        process_started
        process_output
        process_exited
        resource_close_request
        resource_close_acknowledged
        resource_closed
        resource_close_failed
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(base_url:)
        @base_url = base_url
      end

      def call
        version_package = Runtime::Manifest::VersionPackage.call

        {
          "execution_runtime_key" => "nexus",
          "display_name" => "Nexus",
          "execution_runtime_kind" => version_package.fetch("kind"),
          "execution_runtime_fingerprint" => version_package.fetch("execution_runtime_fingerprint"),
          "execution_runtime_connection_metadata" => endpoint_metadata,
          "execution_runtime_capability_payload" => version_package.fetch("capability_payload"),
          "execution_runtime_tool_catalog" => version_package.fetch("tool_catalog"),
          "protocol_version" => version_package.fetch("protocol_version"),
          "sdk_version" => version_package.fetch("sdk_version"),
          "endpoint_metadata" => endpoint_metadata,
          "execution_runtime_contract" => execution_runtime_contract,
          "protocol_methods" => protocol_methods,
          "execution_runtime_plane" => execution_runtime_plane(version_package),
          "version_package" => version_package,
        }
      end

      private

      def endpoint_metadata
        {
          "transport" => "http",
          "base_url" => @base_url,
          "runtime_manifest_path" => "/runtime/manifest",
        }
      end

      def execution_runtime_contract
        {
          "version" => "v1",
          "transport" => "mailbox-first",
          "delivery" => %w[websocket_push poll],
          "methods" => %w[
            execution_assignment
            resource_close_request
          ],
        }
      end

      def protocol_methods
        PROTOCOL_METHOD_IDS.map { |method_id| { "method_id" => method_id } }
      end

      def execution_runtime_tool_catalog
        Runtime::Manifest::VersionPackage.call.fetch("tool_catalog")
      end

      def execution_runtime_plane(version_package)
        {
          "control_plane" => "execution_runtime",
          "protocol_methods" => protocol_methods,
          "capability_payload" => version_package.fetch("capability_payload"),
          "tool_catalog" => version_package.fetch("tool_catalog"),
        }
      end

      def execution_runtime_capability_payload
        Runtime::Manifest::VersionPackage.call.fetch("capability_payload")
      end
    end
  end
end
