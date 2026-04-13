module Conversations
  module Metadata
    class TitleBootstrapPolicy
      DEFAULT_POLICY = {
        "enabled" => true,
        "mode" => "runtime_first",
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(workspace:, agent_definition_version: nil)
        @workspace = workspace
        @agent_definition_version = agent_definition_version
      end

      def call
        normalize_policy(
          DEFAULT_POLICY
            .deep_merge(runtime_default_policy)
            .deep_merge(workspace_override_policy)
        )
      end

      private

      def workspace_override_policy
        normalize_hash(@workspace&.config).dig("metadata", "title_bootstrap") || {}
      end

      def runtime_default_policy
        normalize_hash(@agent_definition_version&.default_canonical_config).dig("metadata", "title_bootstrap") || {}
      end

      def normalize_policy(policy)
        enabled = policy.fetch("enabled", DEFAULT_POLICY.fetch("enabled"))
        mode = policy.fetch("mode", DEFAULT_POLICY.fetch("mode"))

        {
          "enabled" => enabled == false ? false : true,
          "mode" => Workspace::TITLE_BOOTSTRAP_MODES.include?(mode) ? mode : DEFAULT_POLICY.fetch("mode"),
        }
      end

      def normalize_hash(value)
        value.is_a?(Hash) ? value.deep_stringify_keys : {}
      end
    end
  end
end
