module Runtime
  module Manifest
    class PairingManifest
      PROTOCOL_VERSION = "agent-runtime/2026-04-01".freeze
      SDK_VERSION = "fenix-0.1.0".freeze
      DEFAULT_FINGERPRINT = "bundled-fenix-release-0.1.0".freeze
      AGENT_TOOL_CATALOG = [
        {
          "tool_name" => "compact_context",
          "tool_kind" => "agent_observation",
          "operator_group" => "agent_core",
          "resource_identity_kind" => "agent_context",
          "mutates_state" => false,
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/agent/compact_context",
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
          "agent_key" => "fenix",
          "display_name" => "Fenix",
          "fingerprint" => fingerprint,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => SDK_VERSION,
          "endpoint_metadata" => endpoint_metadata,
          "agent_contract" => agent_contract,
          "protocol_methods" => protocol_methods,
          "tool_catalog" => agent_tool_catalog,
          "profile_catalog" => profile_catalog,
          "agent_plane" => agent_plane,
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

      def fingerprint
        ENV["FENIX_RUNTIME_FINGERPRINT"].presence || DEFAULT_FINGERPRINT
      end

      def agent_contract
        {
          "version" => "v1",
          "transport" => "mailbox-first",
          "delivery" => %w[websocket_push poll],
          "methods" => %w[
            prepare_round
            execute_tool
            supervision_status_refresh
            supervision_guidance
          ],
        }
      end

      def protocol_methods
        PROTOCOL_METHOD_IDS.map { |method_id| { "method_id" => method_id } }
      end

      def agent_tool_catalog
        AGENT_TOOL_CATALOG
      end

      def profile_catalog
        allowed_tool_names = agent_tool_catalog.map { |entry| entry.fetch("tool_name") }

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

      def agent_plane
        {
          "control_plane" => "agent",
          "protocol_methods" => protocol_methods,
          "tool_catalog" => agent_tool_catalog,
          "profile_catalog" => profile_catalog,
          "config_schema_snapshot" => CONFIG_SCHEMA_SNAPSHOT,
          "conversation_override_schema_snapshot" => CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT,
          "default_config_snapshot" => DEFAULT_CONFIG_SNAPSHOT,
        }
      end
    end
  end
end
