module ProviderExecution
  class PromptCompactionPolicy
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
      ).fetch("prompt_compaction")
    end
  end
end
