module Conversations
  class ValidateAgentDeploymentTarget
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      agent_deployment:,
      record: nil,
      same_logical_agent_as: nil,
      capability_contract_turn: nil
    )
      @conversation = conversation
      @agent_deployment = agent_deployment
      @record = record || conversation
      @same_logical_agent_as = same_logical_agent_as
      @capability_contract_turn = capability_contract_turn
    end

    def call
      validate_same_installation!
      validate_same_environment!
      validate_same_logical_agent! if @same_logical_agent_as.present?
      validate_capability_contract! if @capability_contract_turn.present?

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

    def validate_same_logical_agent!
      return if @same_logical_agent_as.same_logical_agent?(@agent_deployment)

      raise_invalid!(:agent_deployment, "must belong to the same logical agent installation")
    end

    def validate_capability_contract!
      return if @agent_deployment.preserves_capability_contract?(@capability_contract_turn)

      raise_invalid!(:agent_deployment, "must preserve the paused workflow capability contract")
    end

    def raise_invalid!(attribute, message)
      @record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
