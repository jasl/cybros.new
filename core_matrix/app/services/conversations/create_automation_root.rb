module Conversations
  class CreateAutomationRoot
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, execution_environment:, agent_deployment:)
      @workspace = workspace
      @execution_environment = execution_environment
      @agent_deployment = agent_deployment
    end

    def call
      Conversations::CreateRoot.call(
        workspace: @workspace,
        execution_environment: @execution_environment,
        agent_deployment: @agent_deployment,
        purpose: "automation"
      )
    end
  end
end
