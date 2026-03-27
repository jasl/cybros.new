module Conversations
  class CreateRoot
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, execution_environment:, agent_deployment:, purpose: "interactive")
      @workspace = workspace
      @execution_environment = execution_environment
      @agent_deployment = agent_deployment
      @purpose = purpose
    end

    def call
      ApplicationRecord.transaction do
        create_root_conversation!(
          workspace: @workspace,
          execution_environment: @execution_environment,
          agent_deployment: @agent_deployment,
          purpose: @purpose
        )
      end
    end
  end
end
