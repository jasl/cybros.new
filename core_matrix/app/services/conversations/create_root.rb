module Conversations
  class CreateRoot
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, agent: nil, purpose: "interactive", execution_runtime: nil)
      @workspace = workspace
      @agent = agent || workspace.user_agent_binding.agent
      @purpose = purpose
      @execution_runtime = execution_runtime
    end

    def call
      ApplicationRecord.transaction do
        create_root_conversation!(
          workspace: @workspace,
          agent: @agent,
          purpose: @purpose,
          execution_runtime: @execution_runtime
        )
      end
    end
  end
end
