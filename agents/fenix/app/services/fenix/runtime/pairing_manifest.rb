module Fenix
  module Runtime
    class PairingManifest
      PROTOCOL_VERSION = "agent-program/2026-04-01".freeze
      SDK_VERSION = "fenix-0.1.0".freeze
      EXECUTOR_KIND = "local".freeze
      DEFAULT_EXECUTOR_FINGERPRINT = "bundled-fenix-environment".freeze
      PROGRAM_TOOL_CATALOG = [
        {
          "tool_name" => "compact_context",
          "tool_kind" => "agent_observation",
          "operator_group" => "agent_core",
          "resource_identity_kind" => "agent_context",
          "mutates_state" => false,
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/hooks/compact_context",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "messages" => { "type" => "array" },
              "budget_hints" => { "type" => "object" },
            },
          },
          "result_schema" => {
            "type" => "object",
            "properties" => {
              "messages" => { "type" => "array" },
              "compacted" => { "type" => "boolean" },
            },
          },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ].freeze
      PROTOCOL_METHOD_IDS = %w[
        agent_health
        capabilities_handshake
        capabilities_refresh
        agent_program_completed
        agent_program_failed
        execution_started
        execution_progress
        execution_complete
        execution_fail
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
          "agent_key" => "fenix",
          "display_name" => "Fenix",
          "includes_executor_program" => true,
          "executor_kind" => EXECUTOR_KIND,
          "executor_fingerprint" => executor_fingerprint,
          "executor_connection_metadata" => endpoint_metadata,
          "executor_capability_payload" => executor_capability_payload,
          "executor_tool_catalog" => executor_tool_catalog,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => SDK_VERSION,
          "endpoint_metadata" => endpoint_metadata,
          "program_contract" => program_contract,
          "protocol_methods" => protocol_methods,
          "tool_catalog" => program_tool_catalog,
          "profile_catalog" => profile_catalog,
          "program_plane" => program_plane,
          "executor_plane" => executor_plane,
          "effective_tool_catalog" => effective_tool_catalog,
          "config_schema_snapshot" => CONFIG_SCHEMA_SNAPSHOT,
          "conversation_override_schema_snapshot" => CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT,
          "default_config_snapshot" => DEFAULT_CONFIG_SNAPSHOT,
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

      def executor_fingerprint
        ENV["FENIX_RUNTIME_FINGERPRINT"].presence || DEFAULT_EXECUTOR_FINGERPRINT
      end

      def program_contract
        {
          "version" => "v1",
          "transport" => "mailbox-first",
          "delivery" => %w[websocket_push poll],
          "methods" => %w[prepare_round execute_program_tool],
        }
      end

      def protocol_methods
        PROTOCOL_METHOD_IDS.map { |method_id| { "method_id" => method_id } }
      end

      def program_tool_catalog
        PROGRAM_TOOL_CATALOG
      end

      def executor_tool_catalog
        Fenix::Runtime::SystemToolRegistry.executor_tool_catalog
      end

      def profile_catalog
        allowed_tool_names = effective_tool_catalog.map { |entry| entry.fetch("tool_name") }

        {
          "main" => {
            "label" => "Main",
            "description" => "Primary interactive profile",
            "allowed_tool_names" => allowed_tool_names + RESERVED_SUBAGENT_TOOL_NAMES,
          },
          "researcher" => {
            "label" => "Researcher",
            "description" => "Delegated research profile",
            "default_subagent_profile" => true,
            "allowed_tool_names" => allowed_tool_names + (RESERVED_SUBAGENT_TOOL_NAMES - ["subagent_spawn"]),
          },
        }
      end

      def program_plane
        {
          "control_plane" => "program",
          "protocol_methods" => protocol_methods,
          "tool_catalog" => program_tool_catalog,
          "profile_catalog" => profile_catalog,
          "config_schema_snapshot" => CONFIG_SCHEMA_SNAPSHOT,
          "conversation_override_schema_snapshot" => CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT,
          "default_config_snapshot" => DEFAULT_CONFIG_SNAPSHOT,
        }
      end

      def executor_plane
        {
          "control_plane" => "executor",
          "capability_payload" => executor_capability_payload,
          "tool_catalog" => executor_tool_catalog,
        }
      end

      def executor_capability_payload
        {
          "runtime_foundation" => runtime_foundation,
        }
      end

      def runtime_foundation
        {
          "docker_base_project" => "images/nexus",
          "canonical_host_os" => "ubuntu-24.04",
          "bare_metal_validator" => "bin/check-runtime-host",
          "version_sources" => {
            "ruby" => ".ruby-version",
            "docker_runtime" => "images/nexus/versions.env",
          },
        }
      end

      def effective_tool_catalog
        ordinary_entries = {}
        ordinary_order = []

        [executor_tool_catalog, program_tool_catalog].each do |catalog|
          catalog.each do |entry|
            tool_name = entry.fetch("tool_name")
            next if ordinary_entries.key?(tool_name)

            ordinary_entries[tool_name] = entry
            ordinary_order << tool_name
          end
        end

        ordinary_order.map { |tool_name| ordinary_entries.fetch(tool_name) }
      end
    end
  end
end
