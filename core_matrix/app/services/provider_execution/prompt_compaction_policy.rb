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
      RuntimeFeatures::PolicyResolver.call(
        feature_key: "prompt_compaction",
        workspace: @workspace,
        agent_definition_version: @agent_definition_version
      )
    end
  end
end
