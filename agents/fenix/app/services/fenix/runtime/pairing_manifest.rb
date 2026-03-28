require "socket"

module Fenix
  module Runtime
    class PairingManifest
      PROTOCOL_VERSION = "2026-03-24".freeze
      SDK_VERSION = "fenix-0.1.0".freeze
      PROTOCOL_METHOD_IDS = %w[
        agent_health
        capabilities_handshake
        capabilities_refresh
        execution_started
        execution_progress
        execution_complete
        execution_fail
        resource_close_request
        resource_close_acknowledged
        resource_closed
        resource_close_failed
      ].freeze
      TOOL_CATALOG = [
        {
          "tool_name" => "compact_context",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/hooks/compact_context",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "messages" => { "type" => "array" },
              "budget_hints" => { "type" => "object" },
              "likely_model" => { "type" => "string" },
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
        {
          "tool_name" => "estimate_messages",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/hooks/estimate_messages",
          "input_schema" => { "type" => "object", "properties" => { "messages" => { "type" => "array" } } },
          "result_schema" => { "type" => "object", "properties" => { "message_count" => { "type" => "integer" } } },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
        {
          "tool_name" => "estimate_tokens",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/hooks/estimate_tokens",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "messages" => { "type" => "array" },
              "likely_model" => { "type" => "string" },
            },
          },
          "result_schema" => { "type" => "object", "properties" => { "token_estimate" => { "type" => "integer" } } },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
        {
          "tool_name" => "calculator",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/runtime/calculator",
          "input_schema" => {
            "type" => "object",
            "properties" => {
              "expression" => { "type" => "string" },
            },
          },
          "result_schema" => {
            "type" => "object",
            "properties" => {
              "value" => { "type" => "integer" },
            },
          },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ].freeze
      SUBAGENT_TOOL_NAMES = %w[
        subagent_spawn
        subagent_send
        subagent_wait
        subagent_close
        subagent_list
      ].freeze
      TOOL_NAMES = TOOL_CATALOG.map { |entry| entry.fetch("tool_name") }.freeze
      PROFILE_CATALOG = {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => TOOL_NAMES + SUBAGENT_TOOL_NAMES,
        },
        "researcher" => {
          "label" => "Researcher",
          "description" => "Delegated research profile",
          "allowed_tool_names" => TOOL_NAMES + (SUBAGENT_TOOL_NAMES - ["subagent_spawn"]),
        },
      }.freeze
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
          "research" => { "selector" => "role:researcher" },
        },
        "subagents" => {
          "enabled" => true,
          "allow_nested" => true,
          "max_depth" => 3,
        },
      }.freeze
      ENVIRONMENT_KIND = "local".freeze
      ENVIRONMENT_CAPABILITY_PAYLOAD = {
        "conversation_attachment_upload" => false,
      }.freeze
      ENVIRONMENT_TOOL_CATALOG = [].freeze

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
          "includes_execution_environment" => true,
          "environment_kind" => ENVIRONMENT_KIND,
          "environment_fingerprint" => environment_fingerprint,
          "environment_connection_metadata" => endpoint_metadata,
          "environment_capability_payload" => ENVIRONMENT_CAPABILITY_PAYLOAD,
          "environment_tool_catalog" => ENVIRONMENT_TOOL_CATALOG,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => SDK_VERSION,
          "endpoint_metadata" => endpoint_metadata,
          "protocol_methods" => protocol_methods,
          "tool_catalog" => TOOL_CATALOG,
          "profile_catalog" => PROFILE_CATALOG,
          "agent_plane" => agent_plane,
          "environment_plane" => environment_plane,
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
          "runtime_execution_path" => "/runtime/executions",
        }
      end

      def protocol_methods
        PROTOCOL_METHOD_IDS.map { |method_id| { "method_id" => method_id } }
      end

      def agent_plane
        {
          "runtime_plane" => "agent",
          "protocol_methods" => protocol_methods,
          "tool_catalog" => TOOL_CATALOG,
          "profile_catalog" => PROFILE_CATALOG,
          "config_schema_snapshot" => CONFIG_SCHEMA_SNAPSHOT,
          "conversation_override_schema_snapshot" => CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT,
          "default_config_snapshot" => DEFAULT_CONFIG_SNAPSHOT,
        }
      end

      def environment_plane
        {
          "runtime_plane" => "environment",
          "capability_payload" => ENVIRONMENT_CAPABILITY_PAYLOAD,
          "tool_catalog" => ENVIRONMENT_TOOL_CATALOG,
        }
      end

      def effective_tool_catalog
        ordinary_entries = {}
        ordinary_order = []

        [ENVIRONMENT_TOOL_CATALOG, TOOL_CATALOG].each do |catalog|
          catalog.each do |entry|
            tool_name = entry.fetch("tool_name")
            next if ordinary_entries.key?(tool_name)

            ordinary_entries[tool_name] = entry
            ordinary_order << tool_name
          end
        end

        ordinary_order.map { |tool_name| ordinary_entries.fetch(tool_name) }
      end

      def environment_fingerprint
        "fenix:#{Socket.gethostname}"
      end
    end
  end
end
