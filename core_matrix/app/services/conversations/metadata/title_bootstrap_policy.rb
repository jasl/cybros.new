module Conversations
  module Metadata
    class TitleBootstrapPolicy
      def self.call(...)
        new(...).call
      end

      def initialize(workspace:, agent_definition_version: nil)
        @workspace = workspace
        @agent_definition_version = agent_definition_version
      end

      def call
        RuntimeFeatures::PolicyResolver.call(
          feature_key: "title_bootstrap",
          workspace: @workspace,
          agent_definition_version: @agent_definition_version
        )
      end
    end
  end
end
