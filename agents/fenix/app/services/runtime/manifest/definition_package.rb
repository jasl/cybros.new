require "digest"
require "json"

module Runtime
  module Manifest
    class DefinitionPackage
      PROTOCOL_VERSION = "agent-runtime/2026-04-01".freeze
      SDK_VERSION = "fenix-0.1.0".freeze
      PROMPT_PACK_REF = "fenix/default".freeze
      RESERVED_SUBAGENT_TOOL_NAMES = %w[
        subagent_spawn
        subagent_send
        subagent_wait
        subagent_close
        subagent_list
      ].freeze
      TOOL_CONTRACT = [
        {
          "tool_name" => "compact_context",
          "tool_kind" => "agent_observation",
          "operator_group" => "agent_core",
          "resource_identity_kind" => "agent_context",
          "mutates_state" => false,
          "implementation_source" => "agent",
          "implementation_ref" => "fenix/compact_context",
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
      FEATURE_CONTRACT = [
        {
          "feature_key" => "title_bootstrap",
          "execution_mode" => "direct",
          "lifecycle" => "live",
          "request_schema" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "message_content" => { "type" => "string" },
            },
            "required" => ["message_content"],
          },
          "response_schema" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "title" => { "type" => "string" },
            },
            "required" => ["title"],
          },
          "implementation_ref" => "fenix/title_bootstrap",
        },
      ].freeze
      REQUEST_PREPARATION_CONTRACT = {
        "prompt_compaction" => {
          "consultation_mode" => "direct_optional",
          "workflow_execution" => "supported",
          "lifecycle" => "turn_scoped",
          "consultation_schema" => {
            "type" => "object",
          },
          "artifact_schema" => {
            "type" => "object",
          },
          "implementation_ref" => "fenix/prompt_compaction",
        },
      }.freeze
      PROTOCOL_METHOD_IDS = %w[
        agent_health
        capabilities_handshake
        capabilities_refresh
        agent_completed
        agent_failed
        resource_close_request
        resource_close_acknowledged
        resource_closed
        resource_close_failed
      ].freeze
      CONVERSATION_OVERRIDE_SCHEMA = {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "subagents" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "enabled" => { "type" => "boolean" },
              "allow_nested" => { "type" => "boolean" },
              "max_depth" => { "type" => "integer" },
            },
          },
        },
      }.freeze

      def self.call(...)
        new(...).call
      end

      def call
        settings_contract = workspace_agent_settings_contract
        package_body = {
          "prompt_pack_ref" => PROMPT_PACK_REF,
          "prompt_pack_fingerprint" => prompt_pack_fingerprint,
          "protocol_version" => PROTOCOL_VERSION,
          "sdk_version" => SDK_VERSION,
          "protocol_methods" => protocol_methods,
          "feature_contract" => feature_contract,
          "request_preparation_contract" => request_preparation_contract,
          "tool_contract" => tool_contract,
          "profile_policy" => settings_contract.fetch("profile_policy"),
          "canonical_config_schema" => canonical_config_schema,
          "conversation_override_schema" => conversation_override_schema,
          "workspace_agent_settings_schema" => settings_contract.fetch("schema"),
          "default_workspace_agent_settings" => settings_contract.fetch("defaults"),
          "default_canonical_config" => default_canonical_config,
          "reflected_surface" => reflected_surface,
        }

        package_body.merge(
          "program_manifest_fingerprint" => digest_for(package_body)
        )
      end

      private

      def protocol_methods
        PROTOCOL_METHOD_IDS.map { |method_id| { "method_id" => method_id } }
      end

      def tool_contract
        TOOL_CONTRACT.deep_dup
      end

      def feature_contract
        FEATURE_CONTRACT.deep_dup
      end

      def request_preparation_contract
        REQUEST_PREPARATION_CONTRACT.deep_dup
      end

      def canonical_config_schema
        read_json_config("canonical_config.schema.json")
      end

      def default_canonical_config
        read_json_config("canonical_config.defaults.json")
      end

      def reflected_surface
        read_json_config("reflected_surface.json")
      end

      def conversation_override_schema
        CONVERSATION_OVERRIDE_SCHEMA.deep_dup
      end

      def prompt_pack_fingerprint
        payload = prompt_pack_files.each_with_object({}) do |path, manifest|
          relative_path = path.relative_path_from(Rails.root).to_s
          manifest[relative_path] = Digest::SHA256.hexdigest(path.read)
        end

        digest_for(payload)
      end

      def prompt_pack_files
        @prompt_pack_files ||= Dir[Rails.root.join("prompts/**/*")].sort.filter_map do |path|
          pathname = Pathname.new(path)
          pathname.file? ? pathname : nil
        end
      end

      def read_json_config(filename)
        JSON.parse(Rails.root.join("config", filename).read)
      end

      def digest_for(payload)
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end

      def workspace_agent_settings_contract
        @workspace_agent_settings_contract ||= Runtime::Manifest::WorkspaceAgentSettings.call(
          default_canonical_config: default_canonical_config
        )
      end
    end
  end
end
