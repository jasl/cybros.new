require "securerandom"

module ProviderExecution
  class ExecuteRoundLoop
    DEFAULT_MAX_ROUNDS = 64

    class RoundRequestFailed < StandardError
      attr_reader :error, :duration_ms, :provider_request_id, :messages_count

      def initialize(error:, duration_ms:, provider_request_id:, messages_count:)
        super(error.message)
        @error = error
        @duration_ms = duration_ms
        @provider_request_id = provider_request_id
        @messages_count = messages_count
      end
    end

    class RoundLimitExceeded < StandardError
      attr_reader :max_rounds, :attempted_rounds, :messages_count

      def initialize(max_rounds:, attempted_rounds:, messages_count:)
        super("provider round loop exceeded #{max_rounds} rounds")
        @max_rounds = max_rounds
        @attempted_rounds = attempted_rounds
        @messages_count = messages_count
      end
    end

    Result = Struct.new(
      :dispatch_result,
      :normalized_response,
      :prepared_round,
      :prior_tool_results,
      :output_deltas,
      :messages_count,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, transcript:, adapter: nil, catalog: nil, effective_catalog: nil, program_exchange: nil, max_rounds: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @request_context = ProviderExecution::BuildRequestContext.call(
        turn: workflow_node.turn,
        execution_snapshot: workflow_node.workflow_run.execution_snapshot
      )
      @transcript = Array(transcript).map { |entry| entry.deep_stringify_keys }
      @adapter = adapter
      @effective_catalog = effective_catalog || ProviderCatalog::EffectiveCatalog.new(installation: @workflow_run.installation, catalog: catalog)
      @program_exchange = program_exchange || ProviderExecution::ProgramMailboxExchange.new(agent_deployment: workflow_node.turn.agent_deployment)
      @max_rounds = max_rounds || configured_max_rounds
    end

    def call
      prior_tool_results = []
      round_count = 0
      last_messages_count = @transcript.length
      core_matrix_binding_ids = visible_core_matrix_binding_ids

      loop do
        round_count += 1
        if round_count > @max_rounds
          raise RoundLimitExceeded.new(
            max_rounds: @max_rounds,
            attempted_rounds: round_count,
            messages_count: last_messages_count
          )
        end

        prepared_round = ProviderExecution::PrepareProgramRound.call(
          workflow_node: @workflow_node,
          transcript: @transcript,
          prior_tool_results: prior_tool_results,
          program_exchange: @program_exchange
        )
        last_messages_count = prepared_round.fetch("messages").length
        program_binding_ids = ProviderExecution::MaterializeRoundTools.call(
          workflow_node: @workflow_node,
          tool_catalog: prepared_round.fetch("program_tools")
        ).pluck(:id)
        round_bindings = ToolBinding.where(
          id: (core_matrix_binding_ids + program_binding_ids).uniq
        ).includes(:tool_definition, tool_implementation: :implementation_source).to_a

        round_deltas = []
        dispatch_result = ProviderExecution::DispatchRequest.call(
          workflow_run: @workflow_run,
          request_context: @request_context,
          messages: provider_messages_for(
            prepared_round.fetch("messages"),
            prior_tool_results
          ),
          tools: provider_tools_for(round_bindings),
          tool_choice: round_bindings.any? ? "auto" : nil,
          adapter: @adapter,
          effective_catalog: @effective_catalog,
          provider_request_id: SecureRandom.uuid,
          on_delta: ->(delta) { round_deltas << delta }
        )
        normalized_response = ProviderExecution::NormalizeProviderResponse.call(
          provider_result: dispatch_result.provider_result
        )

        return Result.new(
          dispatch_result: dispatch_result,
          normalized_response: normalized_response,
          prepared_round: prepared_round,
          prior_tool_results: prior_tool_results,
          output_deltas: round_deltas,
          messages_count: prepared_round.fetch("messages").length
        ) if normalized_response.fetch("tool_calls").empty?

        new_tool_results = normalized_response.fetch("tool_calls").map do |tool_call|
          routed_result = ProviderExecution::RouteToolCall.call(
            workflow_node: @workflow_node,
            tool_call: tool_call,
            round_bindings: round_bindings,
            program_exchange: @program_exchange
          )
          ProviderExecution::AppendToolResult.call(
            tool_call: tool_call,
            routed_result: routed_result
          )
        end

        prior_tool_results.concat(new_tool_results)
      rescue ProviderExecution::DispatchRequest::RequestFailed => error
        raise RoundRequestFailed.new(
          error: error.error,
          duration_ms: error.duration_ms,
          provider_request_id: error.provider_request_id,
          messages_count: prepared_round.fetch("messages").length
        )
      rescue ProviderExecution::ProgramMailboxExchange::ExchangeError => error
        raise RoundRequestFailed.new(
          error: error,
          duration_ms: 0,
          provider_request_id: nil,
          messages_count: prepared_round.present? ? prepared_round.fetch("messages").length : @transcript.length
        )
      end
    end

    private

    def provider_tools_for(round_bindings)
      return [] if round_bindings.blank?

      case @request_context.wire_api
      when "responses"
        round_bindings.map do |binding|
          {
            "type" => "function",
            "name" => binding.tool_definition.tool_name,
            "parameters" => binding.tool_implementation.input_schema,
          }
        end
      else
        round_bindings.map do |binding|
          {
            "type" => "function",
            "function" => {
              "name" => binding.tool_definition.tool_name,
              "parameters" => binding.tool_implementation.input_schema,
            },
          }
        end
      end
    end

    def provider_messages_for(base_messages, prior_tool_results)
      messages = Array(base_messages).map { |entry| entry.deep_stringify_keys }
      return messages if prior_tool_results.blank?

      messages + protocol_continuation_entries(prior_tool_results)
    end

    def protocol_continuation_entries(prior_tool_results)
      Array(prior_tool_results).flat_map do |entry|
        normalized_entry = entry.deep_stringify_keys

        case @request_context.wire_api
        when "responses"
          responses_continuation_entries(normalized_entry)
        else
          chat_continuation_entries(normalized_entry)
        end
      end
    end

    def chat_continuation_entries(entry)
      call_id = entry.fetch("call_id")
      arguments_json = JSON.generate(entry.fetch("arguments", {}))

      [
        {
          "role" => "assistant",
          "tool_calls" => [
            {
              "id" => call_id,
              "type" => "function",
              "function" => {
                "name" => entry.fetch("tool_name"),
                "arguments" => arguments_json,
              },
            },
          ],
        },
        {
          "role" => "tool",
          "tool_call_id" => call_id,
          "call_id" => call_id,
          "name" => entry.fetch("tool_name"),
          "content" => serialize_tool_result(entry.fetch("result")),
        },
      ]
    end

    def responses_continuation_entries(entry)
      call_id = entry.fetch("call_id")
      function_call = {
        "type" => "function_call",
        "call_id" => call_id,
        "name" => entry.fetch("tool_name"),
        "arguments" => JSON.generate(entry.fetch("arguments", {})),
      }
      provider_item_id = entry["provider_item_id"]
      function_call["id"] = provider_item_id if provider_item_id.present?

      [
        function_call,
        {
          "type" => "function_call_output",
          "call_id" => call_id,
          "output" => serialize_tool_result(entry.fetch("result")),
        },
      ]
    end

    def serialize_tool_result(result)
      result.is_a?(String) ? result : JSON.generate(result)
    end

    def configured_max_rounds
      @workflow_run.execution_snapshot.provider_execution.dig("loop_settings", "max_rounds").presence || DEFAULT_MAX_ROUNDS
    end

    def visible_core_matrix_binding_ids
      ToolBindings::FreezeForWorkflowNode.call(
        workflow_node: @workflow_node
      ).joins(tool_implementation: :implementation_source).where(
        implementation_sources: { source_kind: "core_matrix" }
      ).distinct.pluck(:id)
    end
  end
end
