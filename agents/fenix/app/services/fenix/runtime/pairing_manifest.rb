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
        resource_close_closed
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
      CONFIG_SCHEMA_SNAPSHOT = {
        "type" => "object",
        "properties" => {
          "sandbox" => { "type" => "string" },
          "interactive" => {
            "type" => "object",
            "properties" => {
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
        },
      }.freeze
      CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT = {
        "type" => "object",
        "properties" => {
          "selector" => { "type" => "string" },
        },
      }.freeze
      DEFAULT_CONFIG_SNAPSHOT = {
        "sandbox" => "workspace-write",
        "interactive" => { "selector" => "role:main" },
        "model_slots" => {
          "research" => { "selector" => "role:researcher" },
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

      def environment_fingerprint
        "fenix:#{Socket.gethostname}"
      end
    end
  end
end
