require "socket"

module Fenix
  module Runtime
    class PairingManifest
      PROTOCOL_VERSION = "2026-03-31".freeze
      SDK_VERSION = "fenix-0.1.0".freeze
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
      CODE_OWNED_TOOL_CATALOG = [
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
          "operator_group" => "agent_core",
          "resource_identity_kind" => "agent_context",
          "mutates_state" => false,
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
          "operator_group" => "agent_core",
          "resource_identity_kind" => "agent_context",
          "mutates_state" => false,
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
          "operator_group" => "agent_core",
          "resource_identity_kind" => "agent_context",
          "mutates_state" => false,
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
      def self.call(...)
        new(...).call
      end

      def self.program_tool_catalog
        new(base_url: "http://runtime.invalid").send(:tool_catalog)
      end

      def self.visible_program_tool_catalog(allowed_tool_names:)
        catalog = program_tool_catalog
        allowed = Array(allowed_tool_names).map(&:to_s).uniq
        return catalog if allowed.empty?

        catalog.select { |entry| allowed.include?(entry.fetch("tool_name")) }
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
          "environment_capability_payload" => environment_capability_payload,
          "environment_tool_catalog" => environment_tool_catalog,
          "operator_groups" => operator_groups,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => SDK_VERSION,
          "endpoint_metadata" => endpoint_metadata,
          "program_contract" => program_contract,
          "protocol_methods" => protocol_methods,
          "tool_catalog" => tool_catalog,
          "profile_catalog" => profile_catalog,
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
        }
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

      def agent_plane
        {
          "runtime_plane" => "agent",
          "protocol_methods" => protocol_methods,
          "tool_catalog" => tool_catalog,
          "profile_catalog" => profile_catalog,
          "config_schema_snapshot" => CONFIG_SCHEMA_SNAPSHOT,
          "conversation_override_schema_snapshot" => CONVERSATION_OVERRIDE_SCHEMA_SNAPSHOT,
          "default_config_snapshot" => DEFAULT_CONFIG_SNAPSHOT,
        }
      end

      def environment_plane
        {
          "runtime_plane" => "environment",
          "capability_payload" => environment_capability_payload,
          "tool_catalog" => environment_tool_catalog,
        }
      end

      def tool_catalog
        @tool_catalog ||= CODE_OWNED_TOOL_CATALOG + plugin_catalog.tool_catalog
      end

      def environment_tool_catalog
        @environment_tool_catalog ||= plugin_catalog.environment_tool_catalog
      end

      def profile_catalog
        tool_names = tool_catalog.map { |entry| entry.fetch("tool_name") }

        {
          "main" => {
            "label" => "Main",
            "description" => "Primary interactive profile",
            "allowed_tool_names" => tool_names + SUBAGENT_TOOL_NAMES,
          },
          "researcher" => {
            "label" => "Researcher",
            "description" => "Delegated research profile",
            "allowed_tool_names" => tool_names + (SUBAGENT_TOOL_NAMES - ["subagent_spawn"]),
          },
        }
      end

      def environment_capability_payload
        {
          "conversation_attachment_upload" => false,
          "runtime_foundation" => runtime_foundation,
          "fixed_port_dev_proxy" => {
            "external_port_env" => "FENIX_DEV_PROXY_PORT",
            "default_external_port" => 3310,
            "routes_file_env" => "FENIX_DEV_PROXY_ROUTES_FILE",
            "path_prefix_template" => "/dev/<process_run_id>",
          },
        }
      end

      def operator_groups
        @operator_groups ||= Fenix::Operator::Catalog.new(tool_catalog: effective_tool_catalog).groups
      end

      def runtime_foundation
        {
          "base_image" => "ubuntu-24.04",
          "toolchains" => %w[ruby node python],
          "versions" => {
            "ruby" => version_file_contents(".ruby-version"),
            "node" => version_file_contents(".node-version"),
            "python" => version_file_contents(".python-version"),
          }.compact,
          "bootstrap_scripts" => [
            "/rails/scripts/bootstrap-runtime-deps.sh",
            "/rails/scripts/bootstrap-runtime-deps-darwin.sh",
          ],
        }
      end

      def effective_tool_catalog
        ordinary_entries = {}
        ordinary_order = []

        [environment_tool_catalog, tool_catalog].each do |catalog|
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

      def plugin_catalog
        @plugin_catalog ||= Fenix::Plugins::Registry.default.catalog
      end

      def version_file_contents(relative_path)
        path = Rails.root.join(relative_path)
        return unless path.exist?

        path.read.strip
      end
    end
  end
end
