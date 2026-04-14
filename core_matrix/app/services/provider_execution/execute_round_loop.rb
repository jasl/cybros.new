require "securerandom"

module ProviderExecution
  class ExecuteRoundLoop
    DEFAULT_MAX_ROUNDS = 64

    class PromptSizeFailure < StandardError
      attr_reader :failure_kind, :messages_count, :failure_scope, :selected_input_message_id

      def initialize(failure_kind:, message:, messages_count:, failure_scope:, selected_input_message_id:)
        super(message)
        @failure_kind = failure_kind
        @messages_count = messages_count
        @failure_scope = failure_scope
        @selected_input_message_id = selected_input_message_id
      end
    end

    class PromptTooLargeForRetry < PromptSizeFailure
      def initialize(messages_count:, selected_input_message_id:)
        super(
          failure_kind: "prompt_too_large_for_retry",
          message: "selected input exceeds the hard input token limit",
          messages_count: messages_count,
          failure_scope: "current_input",
          selected_input_message_id: selected_input_message_id
        )
      end
    end

    class ContextWindowExceededAfterCompaction < PromptSizeFailure
      def initialize(messages_count:, selected_input_message_id:)
        super(
          failure_kind: "context_window_exceeded_after_compaction",
          message: "context window exceeded after compaction",
          messages_count: messages_count,
          failure_scope: "full_context",
          selected_input_message_id: selected_input_message_id
        )
      end
    end

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
      :kind,
      :dispatch_result,
      :normalized_response,
      :prepared_round,
      :prior_tool_results,
      :output_deltas,
      :messages_count,
      :tool_batch_result,
      :prompt_compaction_result,
      keyword_init: true
    ) do
      def final?
        kind == "final"
      end

      def yielded_tool_batch?
        kind == "tool_batch"
      end

      def yielded_prompt_compaction?
        kind == "prompt_compaction"
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, transcript:, adapter: nil, catalog: nil, effective_catalog: nil, agent_request_exchange: nil, request_preparation_exchange: nil, max_rounds: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @request_context = ProviderExecution::BuildRequestContext.call(
        turn: workflow_node.turn,
        execution_snapshot: workflow_node.workflow_run.execution_snapshot
      )
      @transcript = Array(transcript).map { |entry| entry.deep_stringify_keys }
      @adapter = adapter
      @effective_catalog = effective_catalog || ProviderCatalog::EffectiveCatalog.new(installation: @workflow_run.installation, catalog: catalog)
      @agent_request_exchange = agent_request_exchange || ProviderExecution::AgentRequestExchange.new(agent_definition_version: workflow_node.turn.agent_definition_version)
      @request_preparation_exchange = request_preparation_exchange || ProviderExecution::RequestPreparationExchange.new(
        agent_definition_version: workflow_node.turn.agent_definition_version,
        agent_request_exchange: @agent_request_exchange
      )
      @max_rounds = max_rounds || configured_max_rounds
    end

    def call
      prior_tool_results = ProviderExecution::LoadPriorToolResults.call(workflow_node: @workflow_node)
      core_matrix_binding_ids = visible_core_matrix_binding_ids
      prepared_round = ProviderExecution::PrepareAgentRound.call(
        workflow_node: @workflow_node,
        transcript: @transcript,
        agent_request_exchange: @agent_request_exchange
      )
      agent_binding_ids = ProviderExecution::MaterializeRoundTools.call(
        workflow_node: @workflow_node,
        tool_catalog: round_tool_catalog_for(prepared_round)
      ).pluck(:id)
      round_bindings = ToolBinding.where(
        id: (core_matrix_binding_ids + agent_binding_ids).uniq
      ).includes(:tool_definition, tool_implementation: :implementation_source).to_a

      provider_messages = provider_messages_for(
        prepared_round.fetch("messages"),
        prior_tool_results
      )
      guard_result = ProviderExecution::PromptBudgetGuard.call(
        messages: provider_messages,
        request_context: @request_context,
        policy: prompt_compaction_policy,
        selected_input_message: selected_input_message_payload
      )
      prompt_compaction_result = evaluate_prompt_budget!(
        guard_result:,
        prepared_round:,
        prior_tool_results:,
        provider_messages:
      )
      return Result.new(
        kind: "prompt_compaction",
        prepared_round: prepared_round,
        prior_tool_results: prior_tool_results,
        messages_count: provider_messages.length,
        prompt_compaction_result: prompt_compaction_result
      ) if prompt_compaction_result.present?

      round_deltas = []
      dispatch_result = ProviderExecution::DispatchRequest.call(
        workflow_run: @workflow_run,
        workflow_node: @workflow_node,
        request_context: @request_context,
        messages: provider_messages,
        tools: provider_tools_for(round_bindings),
        tool_choice: round_bindings.any? ? "auto" : nil,
        adapter: @adapter,
        effective_catalog: @effective_catalog,
        provider_request_id: SecureRandom.uuid,
        on_delta: ->(delta) { round_deltas << delta }
      )
      normalized_response = ProviderExecution::NormalizeProviderResponse.call(
        provider_result: dispatch_result.provider_result,
        request_context: @request_context
      )
      if normalized_response.fetch("tool_calls").empty? && normalized_response.fetch("output_text").blank?
        raise RoundRequestFailed.new(
          error: SimpleInference::DecodeError.new("provider response must include output text or tool calls"),
          duration_ms: dispatch_result.duration_ms,
          provider_request_id: dispatch_result.provider_request_id,
          messages_count: prepared_round.fetch("messages").length
        )
      end

      return Result.new(
        kind: "final",
        dispatch_result: dispatch_result,
        normalized_response: normalized_response,
        prepared_round: prepared_round,
        prior_tool_results: prior_tool_results,
        output_deltas: round_deltas,
        messages_count: provider_messages.length
      ) if normalized_response.fetch("tool_calls").empty?

      attempted_rounds = current_round_index + 1
      if attempted_rounds > @max_rounds
        raise RoundLimitExceeded.new(
          max_rounds: @max_rounds,
          attempted_rounds: attempted_rounds,
          messages_count: provider_messages.length
        )
      end

      Result.new(
        kind: "tool_batch",
        dispatch_result: dispatch_result,
        normalized_response: normalized_response,
        prepared_round: prepared_round,
        prior_tool_results: prior_tool_results,
        output_deltas: round_deltas,
        messages_count: provider_messages.length,
        tool_batch_result: ProviderExecution::BuildToolExecutionBatch.call(
          workflow_node: @workflow_node,
          tool_calls: normalized_response.fetch("tool_calls"),
          round_bindings: round_bindings
        )
      )
    rescue ProviderExecution::ProviderRequestGovernor::AdmissionRefused
      raise
    rescue ProviderExecution::DispatchRequest::RequestFailed => error
      overflow_result = overflow_recovery_result(
        error: error.error,
        prepared_round: prepared_round,
        prior_tool_results: prior_tool_results,
        provider_messages: provider_messages,
        guard_result: guard_result
      )
      if overflow_result.present?
        return Result.new(
          kind: "prompt_compaction",
          prepared_round: prepared_round,
          prior_tool_results: prior_tool_results,
          messages_count: provider_messages.length,
          prompt_compaction_result: overflow_result
        )
      end

      raise RoundRequestFailed.new(
        error: error.error,
        duration_ms: error.duration_ms,
        provider_request_id: error.provider_request_id,
        messages_count: prepared_round.fetch("messages").length
      )
    rescue ProviderExecution::AgentRequestExchange::ExchangeError => error
      raise RoundRequestFailed.new(
        error: error,
        duration_ms: 0,
        provider_request_id: nil,
        messages_count: prepared_round.present? ? prepared_round.fetch("messages").length : @transcript.length
      )
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

    def round_tool_catalog_for(prepared_round)
      visible_tool_surface = @workflow_run.execution_snapshot.capability_projection.fetch("tool_surface", [])
      visible_tool_names = Array(prepared_round.fetch("visible_tool_names")).map(&:to_s)

      visible_tool_surface.select do |entry|
        visible_tool_names.include?(entry.fetch("tool_name")) && round_bindable_tool_entry?(entry)
      end
    end

    def provider_messages_for(base_messages, prior_tool_results)
      messages = Array(base_messages).map { |entry| entry.deep_stringify_keys }
      return messages if skip_prior_tool_results_append?
      return messages if prior_tool_results.blank?

      messages + protocol_continuation_entries(prior_tool_results)
    end

    def evaluate_prompt_budget!(guard_result:, prepared_round:, prior_tool_results:, provider_messages:)
      decision = guard_result.fetch("decision")
      return if decision == "allow"
      raise prompt_too_large_for_retry(provider_messages.length) if decision == "reject"

      consultation_result = consult_prompt_compaction(
        guard_result:,
        prepared_round:,
        prior_tool_results:,
        provider_messages:
      )
      final_decision = resolve_prompt_compaction_decision(
        guard_result:,
        consultation_result:
      )

      case final_decision
      when "allow"
        nil
      when "compact"
        raise context_window_exceeded_after_compaction(provider_messages.length) if prompt_compaction_attempt_limit_reached?

        build_prompt_compaction_result(
          guard_result: guard_result,
          consultation_result: consultation_result,
          consultation_reason: consultation_reason_for(guard_result),
          provider_messages: provider_messages
        )
      else
        raise explicit_budget_failure(guard_result, provider_messages.length)
      end
    end

    def consult_prompt_compaction(guard_result:, prepared_round:, prior_tool_results:, provider_messages:, consultation_reason: consultation_reason_for(guard_result))
      if runtime_consultation_supported?
        @request_preparation_exchange.consult_prompt_compaction(
          payload: prompt_compaction_consult_payload(
            guard_result:,
            consultation_reason: consultation_reason,
            prepared_round:,
            prior_tool_results:,
            provider_messages:
          )
        )
      else
        embedded_consultation_result(guard_result, consultation_reason: consultation_reason)
      end
    end

    def prompt_compaction_consult_payload(guard_result:, consultation_reason:, prepared_round:, prior_tool_results:, provider_messages:)
      {
        "protocol_version" => "agent-runtime/2026-04-01",
        "request_kind" => "consult_prompt_compaction",
        "task" => {
          "workflow_run_id" => @workflow_run.public_id,
          "workflow_node_id" => @workflow_node.public_id,
          "conversation_id" => @workflow_run.conversation.public_id,
          "turn_id" => @workflow_run.turn.public_id,
          "kind" => "turn_step",
        },
        "prompt_compaction" => {
          "consultation_reason" => consultation_reason,
          "candidate_messages" => provider_messages,
          "selected_input_message_id" => @workflow_run.execution_snapshot.selected_input_message_id,
          "guard_result" => guard_result,
          "policy" => prompt_compaction_policy,
          "capability" => prompt_compaction_capability,
          "budget_hints" => @workflow_run.execution_snapshot.budget_hints,
          "preservation_invariants" => ProviderExecution::PromptCompactionStrategy::PRESERVATION_INVARIANTS,
        },
        "provider_context" => @workflow_run.execution_snapshot.provider_context,
        "runtime_context" => @workflow_run.execution_snapshot.runtime_context.merge(
          "logical_work_id" => "prompt-compaction-consult:#{@workflow_node.public_id}",
          "attempt_no" => 1
        ),
        "round_context" => {
          "messages" => prepared_round.fetch("messages"),
          "summary_artifacts" => prepared_round.fetch("summary_artifacts", []),
          "trace" => prepared_round.fetch("trace", []),
          "prior_tool_results" => prior_tool_results,
        },
      }
    end

    def embedded_consultation_result(guard_result, consultation_reason:)
      strategy = prompt_compaction_policy["strategy"].presence || "runtime_first"
      decision =
        if consultation_reason == "overflow_recovery"
          strategy.in?(%w[disabled runtime_required]) ? "reject" : "compact"
        else
          case strategy
          when "disabled"
            guard_result.fetch("decision") == "compact_required" ? "reject" : "skip"
          else
            guard_result.fetch("decision") == "consult" ? "skip" : "compact"
          end
        end

      {
        "status" => "ok",
        "decision" => decision,
        "source" => "embedded",
        "diagnostics" => {
          "reason" => consultation_reason,
          "fallback_mode" => strategy,
        },
      }
    end

    def resolve_prompt_compaction_decision(guard_result:, consultation_result:)
      consultation_decision = consultation_result["decision"].to_s
      return "reject" if consultation_decision == "reject"
      return "compact" if guard_result.fetch("decision") == "compact_required"
      return "compact" if consultation_decision == "compact"

      "allow"
    end

    def consultation_reason_for(guard_result)
      guard_result.fetch("decision") == "consult" ? "soft_threshold" : "hard_limit"
    end

    def overflow_recovery_result(error:, prepared_round:, prior_tool_results:, provider_messages:, guard_result:)
      return unless provider_overflow_error?(error)

      raise context_window_exceeded_after_compaction(provider_messages.length) if overflow_recovery_attempt_limit_reached?

      overflow_guard_result = overflow_guard_result_for(guard_result, error)
      consultation_result = consult_prompt_compaction(
        guard_result: overflow_guard_result,
        prepared_round: prepared_round,
        prior_tool_results: prior_tool_results,
        provider_messages: provider_messages,
        consultation_reason: "overflow_recovery"
      )

      return build_prompt_compaction_result(
        guard_result: overflow_guard_result,
        consultation_result: consultation_result,
        consultation_reason: "overflow_recovery",
        provider_messages: provider_messages
      ) if consultation_result["decision"].to_s == "compact"

      raise context_window_exceeded_after_compaction(provider_messages.length)
    end

    def build_prompt_compaction_result(guard_result:, consultation_result:, consultation_reason:, provider_messages:)
      {
        "guard_result" => guard_result,
        "consultation" => consultation_result,
        "consultation_reason" => consultation_reason,
        "candidate_messages" => provider_messages,
        "selected_input_message_id" => selected_input_message_public_id,
        "budget_hints" => @workflow_run.execution_snapshot.budget_hints,
        "policy" => prompt_compaction_policy,
        "capability" => prompt_compaction_capability,
      }
    end

    def overflow_guard_result_for(guard_result, error)
      base = guard_result.deep_stringify_keys

      base.merge(
        "decision" => "compact_required",
        "failure_scope" => "full_context",
        "retry_mode" => "workflow_compaction",
        "diagnostics" => base.fetch("diagnostics", {}).merge(
          "overflow_recovery" => true,
          "provider_overflow_status" => error.respond_to?(:status) ? error.status.to_i : nil,
          "provider_overflow_code" => provider_overflow_code_for(error)
        ).compact
      )
    end

    def explicit_budget_failure(guard_result, messages_count)
      if guard_result["failure_scope"].to_s == "current_input"
        prompt_too_large_for_retry(messages_count)
      else
        context_window_exceeded_after_compaction(messages_count)
      end
    end

    def prompt_too_large_for_retry(messages_count)
      PromptTooLargeForRetry.new(
        messages_count: messages_count,
        selected_input_message_id: selected_input_message_public_id
      )
    end

    def context_window_exceeded_after_compaction(messages_count)
      ContextWindowExceededAfterCompaction.new(
        messages_count: messages_count,
        selected_input_message_id: selected_input_message_public_id
      )
    end

    def prompt_compaction_attempt_limit_reached?
      current_prompt_compaction_attempt_no >= ProviderExecution::PromptBudgetGuard::MAX_COMPACTION_ATTEMPTS
    end

    def overflow_recovery_attempt_limit_reached?
      current_overflow_recovery_attempt_no >= ProviderExecution::PromptBudgetGuard::MAX_OVERFLOW_RECOVERY_ATTEMPTS
    end

    def current_prompt_compaction_attempt_no
      workflow_node_metadata.fetch("prompt_compaction_attempt_no", 0).to_i
    end

    def current_overflow_recovery_attempt_no
      workflow_node_metadata.fetch("overflow_recovery_attempt_no", 0).to_i
    end

    def workflow_node_metadata
      @workflow_node_metadata ||= @workflow_node.metadata.is_a?(Hash) ? @workflow_node.metadata.deep_stringify_keys : {}
    end

    def selected_input_message_public_id
      @workflow_run.execution_snapshot.selected_input_message_id
    end

    def provider_overflow_error?(error)
      return false unless error.is_a?(SimpleInference::HTTPError)

      body_text = [error.message, error.raw_body, error.body].compact.join(" ").downcase

      ProviderExecution::PromptOverflowDetection.matches?(status: error.status, body_text: body_text)
    end

    def provider_overflow_code_for(error)
      return unless error.respond_to?(:body)

      body = error.body
      case body
      when Hash
        body.deep_stringify_keys.dig("error", "code")
      else
        nil
      end
    end

    def prompt_compaction_policy
      @prompt_compaction_policy ||= begin
        contract = @workflow_run.execution_snapshot.provider_context.dig("request_preparation", "prompt_compaction")
        contract.is_a?(Hash) ? contract.fetch("policy", {}) : {}
      end
    end

    def prompt_compaction_capability
      @prompt_compaction_capability ||= begin
        contract = @workflow_run.execution_snapshot.provider_context.dig("request_preparation", "prompt_compaction")
        contract.is_a?(Hash) ? contract.fetch("capability", {}) : {}
      end
    end

    def runtime_consultation_supported?
      strategy = prompt_compaction_policy["strategy"].presence || "runtime_first"
      return false if strategy.in?(%w[disabled embedded_only])

      prompt_compaction_capability["available"] == true &&
        prompt_compaction_capability["consultation_mode"].to_s.in?(%w[direct_optional direct_required])
    end

    def selected_input_message_payload
      selected_input = @workflow_run.turn.selected_input_message
      return if selected_input.blank?

      {
        "role" => selected_input.role == "agent" ? "assistant" : selected_input.role,
        "content" => selected_input.content,
      }
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
      provider_execution = @workflow_run.execution_snapshot.provider_execution

      provider_execution.dig("loop_policy", "max_rounds").presence || DEFAULT_MAX_ROUNDS
    end

    def current_round_index
      value = @workflow_node.provider_round_index
      value.present? ? value.to_i : 1
    end

    def visible_core_matrix_binding_ids
      ToolBindings::FreezeForWorkflowNode.call(
        workflow_node: @workflow_node
      ).joins(tool_implementation: :implementation_source).where(
        implementation_sources: { source_kind: "core_matrix" }
      ).distinct.pluck(:id)
    end

    def round_bindable_tool_entry?(entry)
      tool_name = entry.fetch("tool_name")
      implementation_source = entry.fetch("implementation_source", nil)

      return false if implementation_source == "core_matrix"
      return false if tool_name.start_with?(AgentDefinitionVersion::RESERVED_CORE_MATRIX_PREFIX)
      return false if RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES.include?(tool_name)

      true
    end

    def skip_prior_tool_results_append?
      @workflow_node.metadata.is_a?(Hash) &&
        @workflow_node.metadata.deep_stringify_keys["prompt_compaction_includes_prior_tool_results"] == true
    end
  end
end
