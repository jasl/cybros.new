module Nexus
  module Runtime
    module Manifest
      class PairingManifest
        PROTOCOL_VERSION = "agent-runtime/2026-04-01".freeze
        SDK_VERSION = "nexus-0.1.0".freeze
        EXECUTION_RUNTIME_KIND = "local".freeze
        DEFAULT_EXECUTION_RUNTIME_FINGERPRINT = "bundled-nexus-environment".freeze
        PROTOCOL_METHOD_IDS = %w[
          agent_health
          capabilities_handshake
          capabilities_refresh
          agent_completed
          agent_failed
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
        CONFIG_SCHEMA_SNAPSHOT = {
          "type" => "object",
          "properties" => {
            "sandbox" => { "type" => "string" },
            "interactive" => {
              "type" => "object",
              "properties" => {
                "profile" => { "type" => "string" },
                "selector" => { "type" => "string" },
              },
            },
            "model_slots" => {
              "type" => "object",
              "additionalProperties" => {
                "type" => "object",
                "properties" => {
                  "selector" => { "type" => "string" },
                },
              },
            },
            "subagents" => {
              "type" => "object",
              "properties" => {
                "enabled" => { "type" => "boolean" },
                "allow_nested" => { "type" => "boolean" },
                "max_depth" => { "type" => "integer" },
              },
            },
          },
        }.freeze
        CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT = {
          "type" => "object",
          "properties" => {
            "subagents" => {
              "type" => "object",
              "properties" => {
                "enabled" => { "type" => "boolean" },
                "allow_nested" => { "type" => "boolean" },
                "max_depth" => { "type" => "integer" },
              },
            },
          },
        }.freeze
        DEFAULT_CONFIG_SNAPSHOT = {
          "sandbox" => "workspace-write",
          "interactive" => {
            "profile" => "main",
            "selector" => "role:main",
          },
          "model_slots" => {
            "summary" => { "selector" => "role:summary" },
          },
          "subagents" => {
            "enabled" => true,
            "allow_nested" => true,
            "max_depth" => 3,
          },
        }.freeze
        RESERVED_SUBAGENT_TOOL_NAMES = %w[
          subagent_spawn
          subagent_send
          subagent_wait
          subagent_close
          subagent_list
        ].freeze

        def self.call(...)
          new(...).call
        end

        def initialize(base_url:)
          @base_url = base_url
        end

        def call
          {
            "execution_runtime_key" => "nexus",
            "display_name" => "Nexus",
            "execution_runtime_kind" => EXECUTION_RUNTIME_KIND,
            "execution_runtime_fingerprint" => execution_runtime_fingerprint,
            "execution_runtime_connection_metadata" => endpoint_metadata,
            "execution_runtime_capability_payload" => execution_runtime_capability_payload,
            "execution_runtime_tool_catalog" => execution_runtime_tool_catalog,
            "protocol_version" => PROTOCOL_VERSION,
            "sdk_version" => SDK_VERSION,
            "endpoint_metadata" => endpoint_metadata,
            "execution_runtime_contract" => execution_runtime_contract,
            "protocol_methods" => protocol_methods,
            "execution_runtime_plane" => execution_runtime_plane,
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

        def execution_runtime_fingerprint
          ENV["NEXUS_RUNTIME_FINGERPRINT"].presence || DEFAULT_EXECUTION_RUNTIME_FINGERPRINT
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
          Nexus::ExecutionRuntime::SystemToolRegistry.execution_runtime_tool_catalog
        end

        def execution_runtime_plane
          {
            "control_plane" => "execution_runtime",
            "protocol_methods" => protocol_methods,
            "capability_payload" => execution_runtime_capability_payload,
            "tool_catalog" => execution_runtime_tool_catalog,
          }
        end

        def execution_runtime_capability_payload
          {
            "runtime_foundation" => {
              "docker_base_project" => "images/nexus",
              "canonical_host_os" => "ubuntu-24.04",
              "bare_metal_validator" => "bin/check-runtime-host",
            },
          }
        end
      end
    end
  end
end
