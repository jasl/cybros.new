module Conversations
  class CreateAutomationRoot
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, agent: nil, **_ignored)
      @workspace = workspace
      @agent = agent
    end

    def call
      Conversations::CreateRoot.call(
        workspace: @workspace,
        agent: @agent,
        purpose: "automation"
      )
    end
  end
end
