module Runtime
  module Manifest
    class PairingManifest
      def self.call(...)
        new(...).call
      end

      def initialize(base_url:)
        @base_url = base_url
      end

      def call
        definition_package = Runtime::Manifest::DefinitionPackage.call

        {
          "agent_key" => "fenix",
          "display_name" => "Fenix",
          "fingerprint" => definition_package.fetch("program_manifest_fingerprint"),
          "protocol_version" => definition_package.fetch("protocol_version"),
          "sdk_version" => definition_package.fetch("sdk_version"),
          "endpoint_metadata" => endpoint_metadata,
          "agent_contract" => agent_contract,
          "protocol_methods" => definition_package.fetch("protocol_methods"),
          "feature_contract" => definition_package.fetch("feature_contract"),
          "request_preparation_contract" => definition_package.fetch("request_preparation_contract"),
          "tool_contract" => definition_package.fetch("tool_contract"),
          "profile_policy" => definition_package.fetch("profile_policy"),
          "agent_plane" => agent_plane(definition_package),
          "canonical_config_schema" => definition_package.fetch("canonical_config_schema"),
          "conversation_override_schema" => definition_package.fetch("conversation_override_schema"),
          "workspace_agent_settings_schema" => definition_package.fetch("workspace_agent_settings_schema"),
          "default_workspace_agent_settings" => definition_package.fetch("default_workspace_agent_settings"),
          "default_canonical_config" => definition_package.fetch("default_canonical_config"),
          "definition_package" => definition_package,
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

      def agent_contract
        {
          "version" => "v1",
          "transport" => "mailbox-first",
          "delivery" => %w[websocket_push poll],
          "methods" => %w[
            prepare_round
            consult_prompt_compaction
            execute_prompt_compaction
            execute_tool
            execute_feature
            supervision_status_refresh
            supervision_guidance
          ],
        }
      end

      def protocol_methods
        Runtime::Manifest::DefinitionPackage.call.fetch("protocol_methods")
      end

      def agent_plane(definition_package)
        {
          "control_plane" => "agent",
          "protocol_methods" => definition_package.fetch("protocol_methods"),
          "feature_contract" => definition_package.fetch("feature_contract"),
          "request_preparation_contract" => definition_package.fetch("request_preparation_contract"),
          "tool_contract" => definition_package.fetch("tool_contract"),
          "profile_policy" => definition_package.fetch("profile_policy"),
          "canonical_config_schema" => definition_package.fetch("canonical_config_schema"),
          "conversation_override_schema" => definition_package.fetch("conversation_override_schema"),
          "workspace_agent_settings_schema" => definition_package.fetch("workspace_agent_settings_schema"),
          "default_workspace_agent_settings" => definition_package.fetch("default_workspace_agent_settings"),
          "default_canonical_config" => definition_package.fetch("default_canonical_config"),
        }
      end
    end
  end
end
