module Runtime
  module Manifest
    class VersionPackage
      PROTOCOL_VERSION = "agent-runtime/2026-04-01".freeze
      SDK_VERSION = "nexus-0.1.0".freeze
      EXECUTION_RUNTIME_KIND = "local".freeze
      DEFAULT_EXECUTION_RUNTIME_FINGERPRINT = "bundled-nexus-environment".freeze

      def self.call(...)
        new(...).call
      end

      def call
        {
          "execution_runtime_fingerprint" => execution_runtime_fingerprint,
          "kind" => EXECUTION_RUNTIME_KIND,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => SDK_VERSION,
          "capability_payload" => capability_payload,
          "tool_catalog" => tool_catalog,
          "reflected_host_metadata" => reflected_host_metadata,
        }
      end

      private

      def execution_runtime_fingerprint
        ENV["NEXUS_RUNTIME_FINGERPRINT"].presence || DEFAULT_EXECUTION_RUNTIME_FINGERPRINT
      end

      def capability_payload
        {
          "runtime_foundation" => {
            "docker_base_project" => "images/nexus",
            "canonical_host_os" => "ubuntu-24.04",
            "bare_metal_validator" => "bin/check-runtime-host",
          },
        }
      end

      def tool_catalog
        SystemToolRegistry.execution_runtime_tool_catalog
      end

      def reflected_host_metadata
        {
          "display_name" => "Nexus",
          "host_role" => "pairing-based execution runtime",
        }
      end
    end
  end
end
