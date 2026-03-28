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
      Conversations::WithMutableStateLock.call(
        conversation: @conversation,
        record: @conversation,
        retained_message: "must be retained before switching agent deployment",
        active_message: "must be active before switching agent deployment",
        closing_message: "must not switch agent deployment while close is in progress"
      ) do |conversation|
        validate_target!(conversation)

        ApplicationRecord.transaction do
          conversation.update!(agent_deployment: @agent_deployment)

          Result.new(
            conversation: conversation,
            runtime_contract: Conversations::RefreshRuntimeContract.call(conversation: conversation)
          )
        end
      end
    end

    private

    def validate_target!(conversation)
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: conversation,
        agent_deployment: @agent_deployment
      )
    end
  end
end
