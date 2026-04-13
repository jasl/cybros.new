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
        WorkspaceFeatures::Resolver.call(
          workspace: @workspace,
          agent_definition_version: @agent_definition_version
        ).fetch("title_bootstrap")
      end
    end
  end
end
