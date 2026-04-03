module Conversations
  class CreateAutomationRoot
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, agent_program: nil, **_ignored)
      @workspace = workspace
      @agent_program = agent_program
    end

    def call
      Conversations::CreateRoot.call(
        workspace: @workspace,
        agent_program: @agent_program,
        purpose: "automation"
      )
    end
  end
end
