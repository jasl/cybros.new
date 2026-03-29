module Conversations
  class ValidateAgentDeploymentTarget
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      agent_deployment:,
      record: nil
    )
      @conversation = conversation
      @agent_deployment = agent_deployment
      @record = record || conversation
    end

    def call
      validate_same_installation!
      validate_same_environment!

      true
    end

    private

    def validate_same_installation!
      return if @agent_deployment.installation_id == @conversation.installation_id

      raise_invalid!(:agent_deployment, "must belong to the same installation")
    end

    def validate_same_environment!
      return if @agent_deployment.execution_environment_id == @conversation.execution_environment_id

      raise_invalid!(:agent_deployment, "must belong to the bound execution environment")
    end

    def raise_invalid!(attribute, message)
      @record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
