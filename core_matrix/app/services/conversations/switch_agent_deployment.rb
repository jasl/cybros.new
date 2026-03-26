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
      unless @agent_deployment.installation_id == @conversation.installation_id
        @conversation.errors.add(:agent_deployment, "must belong to the same installation")
        raise ActiveRecord::RecordInvalid, @conversation
      end

      return if @agent_deployment.execution_environment_id == @conversation.execution_environment_id

      @conversation.errors.add(:agent_deployment, "must belong to the bound execution environment")
      raise ActiveRecord::RecordInvalid, @conversation
    end
  end
end
