module ProviderExecution
  class PrepareProgramRound
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, transcript:, prior_tool_results:, program_exchange: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @program_exchange = program_exchange || ProviderExecution::ProgramMailboxExchange.new(agent_deployment: workflow_node.turn.agent_deployment)
      @transcript = Array(transcript).map { |entry| entry.deep_stringify_keys }
      @prior_tool_results = Array(prior_tool_results).map { |entry| entry.deep_stringify_keys }
    end

    def call
      response = @program_exchange.prepare_round(payload: request_payload)
      validate_response!(response)
      response
    end

    private

    def request_payload
      {
        "conversation_id" => @workflow_run.conversation.public_id,
        "turn_id" => @workflow_run.turn.public_id,
        "workflow_run_id" => @workflow_run.public_id,
        "workflow_node_id" => @workflow_node.public_id,
        "transcript" => @transcript,
        "context_imports" => @workflow_run.context_imports,
        "prior_tool_results" => @prior_tool_results,
        "budget_hints" => @workflow_run.budget_hints,
        "provider_execution" => @workflow_run.provider_execution,
        "model_context" => @workflow_run.model_context,
        "agent_context" => @workflow_run.execution_snapshot.agent_context,
        "runtime_identity" => {
          "deployment_public_id" => @workflow_run.turn.agent_deployment.public_id,
        },
      }
    end

    def validate_response!(response)
      raise ProviderExecution::ProgramMailboxExchange::ProtocolError.new(code: "invalid_prepare_round_response", message: "agent program prepare_round response must include messages") unless response["messages"].is_a?(Array)
      raise ProviderExecution::ProgramMailboxExchange::ProtocolError.new(code: "invalid_prepare_round_response", message: "agent program prepare_round response must include program_tools") unless response["program_tools"].is_a?(Array)
    end
  end
end
