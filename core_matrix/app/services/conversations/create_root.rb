module Conversations
  class CreateRoot
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(workspace_agent:, workspace: nil, agent: nil, purpose: "interactive", execution_runtime: nil)
      @workspace_agent = workspace_agent
      @workspace = workspace || workspace_agent.workspace
      @agent = agent || workspace_agent.agent
      @purpose = purpose
      @execution_runtime = execution_runtime
    end

    def call
      ApplicationRecord.transaction do
        create_root_conversation!(
          workspace_agent: @workspace_agent,
          workspace: @workspace,
          agent: @agent,
          purpose: @purpose,
          execution_runtime: @execution_runtime
        )
      end
    end
  end
end
