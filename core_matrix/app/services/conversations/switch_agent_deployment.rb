module Conversations
  class SwitchAgentDeployment
    Result = Struct.new(:conversation, :runtime_contract, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, agent_deployment:)
      @conversation = conversation
      @agent_deployment = agent_deployment
    end

    def call
      validate_target!

      ApplicationRecord.transaction do
        @conversation.update!(agent_deployment: @agent_deployment)

        Result.new(
          conversation: @conversation,
          runtime_contract: Conversations::RefreshRuntimeContract.call(conversation: @conversation)
        )
      end
    end

    private

    def validate_target!
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: @conversation,
        agent_deployment: @agent_deployment
      )
    end
  end
end
