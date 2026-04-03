module ProviderExecution
  class PrepareProgramRound
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, transcript:, prior_tool_results:, program_exchange: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @program_exchange = program_exchange || ProviderExecution::ProgramMailboxExchange.new(agent_program_version: workflow_node.turn.agent_program_version)
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
        "protocol_version" => "agent-program/2026-04-01",
        "request_kind" => "prepare_round",
        "task" => {
          "workflow_run_id" => @workflow_run.public_id,
          "workflow_node_id" => @workflow_node.public_id,
          "conversation_id" => @workflow_run.conversation.public_id,
          "turn_id" => @workflow_run.turn.public_id,
          "kind" => "turn_step",
        },
        "conversation_projection" => @workflow_run.execution_snapshot.conversation_projection.merge(
          "messages" => @transcript,
          "prior_tool_results" => @prior_tool_results
        ),
        "capability_projection" => @workflow_run.execution_snapshot.capability_projection,
        "provider_context" => @workflow_run.execution_snapshot.provider_context,
        "runtime_context" => {
          "runtime_plane" => "program",
          "logical_work_id" => "prepare-round:#{@workflow_node.public_id}",
          "attempt_no" => 1,
          "agent_program_version_id" => @workflow_run.turn.agent_program_version.public_id,
        },
      }
    end

    def validate_response!(response)
      raise ProviderExecution::ProgramMailboxExchange::ProtocolError.new(code: "invalid_prepare_round_response", message: "agent program prepare_round response must include messages") unless response["messages"].is_a?(Array)
      raise ProviderExecution::ProgramMailboxExchange::ProtocolError.new(code: "invalid_prepare_round_response", message: "agent program prepare_round response must include tool_surface") unless response["tool_surface"].is_a?(Array)
    end
  end
end
