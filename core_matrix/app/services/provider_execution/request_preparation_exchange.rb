module ProviderExecution
  class RequestPreparationExchange
    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, agent_request_exchange: nil)
      @agent_definition_version = agent_definition_version
      @agent_request_exchange = agent_request_exchange || ProviderExecution::AgentRequestExchange.new(
        agent_definition_version: @agent_definition_version
      )
    end

    def consult_prompt_compaction(payload:)
      @agent_request_exchange.consult_prompt_compaction(payload:)
    end

    def execute_prompt_compaction(payload:)
      @agent_request_exchange.execute_prompt_compaction(payload:)
    end
  end
end
