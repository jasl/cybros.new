require "securerandom"

module ProviderExecution
  class ExecuteTurnStep
    StaleExecutionError = ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError
    Result = ProviderExecution::PersistTurnStepSuccess::Result

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, messages:, adapter: nil, catalog: nil, effective_catalog: nil, agent_request_exchange: nil, request_preparation_exchange: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
      @messages = normalize_messages(messages)
      @adapter = adapter
      @agent_request_exchange = agent_request_exchange
      @request_preparation_exchange = request_preparation_exchange
      @effective_catalog = effective_catalog || ProviderCatalog::EffectiveCatalog.new(installation: @workflow_run.installation, catalog: catalog)
      @request_context = BuildRequestContext.call(
        turn: @turn,
        execution_snapshot: @workflow_run.execution_snapshot
      )
      @provider_request_id = SecureRandom.uuid
    end

    def call
      raise_invalid!(@workflow_node, :node_type, "must be a turn_step workflow node") unless @workflow_node.node_type == "turn_step"
      raise_invalid!(@workflow_run, :lifecycle_state, "must be active to execute provider work") unless @workflow_run.active?
      raise_invalid!(@workflow_run, :wait_state, "must be ready to execute provider work") unless @workflow_run.ready?
      raise_invalid!(@turn, :lifecycle_state, "must be active to execute provider work") unless @turn.active?
      raise_invalid!(@workflow_node, :base, "must provide at least one provider message") if @messages.empty?
      raise_invalid!(@workflow_node, :base, "already has terminal execution status") if @workflow_node.terminal?
      unless @workflow_node.pending? || @workflow_node.queued? || @workflow_node.running?
        raise_invalid!(@workflow_node, :lifecycle_state, "must be pending or queued before provider execution")
      end

      claim_running!
      broadcast_workflow_node_event!("runtime.workflow_node.started", state: "running")
      raise prompt_compaction_preflight_failure if prompt_compaction_preflight_failure.present?

      loop_result = ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: @workflow_node,
        transcript: @messages,
        adapter: @adapter,
        effective_catalog: @effective_catalog,
        agent_request_exchange: @agent_request_exchange,
        request_preparation_exchange: @request_preparation_exchange,
        on_output_delta: streaming_output_enabled? ? method(:handle_output_delta) : nil
      )

      if loop_result.final?
        result = ProviderExecution::PersistTurnStepSuccess.call(
          workflow_node: @workflow_node,
          request_context: @request_context,
          provider_result: loop_result.dispatch_result.provider_result,
          provider_request_id: loop_result.dispatch_result.provider_request_id,
          messages_count: loop_result.messages_count,
          duration_ms: loop_result.dispatch_result.duration_ms,
          output_content: loop_result.normalized_response.fetch("output_text")
        )
        finalize_output_stream!(loop_result:, result:)
        broadcast_workflow_node_event!(
          "runtime.workflow_node.completed",
          state: "completed",
          provider_request_id: loop_result.dispatch_result.provider_request_id,
          output_message_id: result.output_message.public_id
        )
        result
      elsif loop_result.yielded_prompt_compaction?
        fail_output_stream_if_started!(
          code: "prompt_compaction",
          message: "assistant output superseded by prompt compaction"
        )
        result = ProviderExecution::PersistTurnStepPromptCompactionYield.call(
          workflow_node: @workflow_node,
          prompt_compaction_result: loop_result.prompt_compaction_result
        )
        broadcast_workflow_node_event!(
          "runtime.workflow_node.completed",
          state: "completed"
        )
        result
      else
        fail_output_stream_if_started!(
          code: "tool_continuation",
          message: "assistant output superseded by tool continuation"
        )
        result = ProviderExecution::PersistTurnStepYield.call(
          workflow_node: @workflow_node,
          request_context: @request_context,
          provider_result: loop_result.dispatch_result.provider_result,
          provider_request_id: loop_result.dispatch_result.provider_request_id,
          messages_count: loop_result.messages_count,
          duration_ms: loop_result.dispatch_result.duration_ms,
          tool_batch_result: loop_result.tool_batch_result,
          round_bindings: ToolBinding.where(
            workflow_node: @workflow_node
          ).includes(:tool_definition, :tool_implementation).to_a
        )
        broadcast_workflow_node_event!(
          "runtime.workflow_node.completed",
          state: "completed",
          provider_request_id: loop_result.dispatch_result.provider_request_id
        )
        result
      end
    rescue ProviderExecution::AgentRequestExchange::PendingResponse => pending
      broadcast_workflow_node_event!(
        "runtime.workflow_node.waiting",
        state: "waiting",
        wait_reason_kind: "agent_request",
        mailbox_item_id: pending.mailbox_item_public_id,
        logical_work_id: pending.logical_work_id,
        request_kind: pending.request_kind
      )
      @workflow_node.reload
    rescue ProviderExecution::ProviderRequestGovernor::AdmissionRefused => error
      fail_output_stream_if_started!(
        code: "provider_request_rejected",
        message: error.message
      )
      if @workflow_run.reload.canceled? || @turn.reload.canceled?
        raise StaleExecutionError, "provider execution result is stale"
      end

      failure_result = ProviderExecution::PersistTurnStepFailure.call(
        workflow_node: @workflow_node,
        request_context: @request_context,
        error: error,
        provider_request_id: @provider_request_id,
        messages_count: @messages.length,
        duration_ms: 0
      )
      handle_failure_outcome!(failure_result.failure_outcome)
      @workflow_node.reload
    rescue ProviderExecution::ExecuteRoundLoop::RoundRequestFailed => dispatch_error
      fail_output_stream_if_started!(
        code: "provider_request_failed",
        message: dispatch_error.error.message
      )
      failure_result = ProviderExecution::PersistTurnStepFailure.call(
        workflow_node: @workflow_node,
        request_context: @request_context,
        error: dispatch_error.error,
        provider_request_id: dispatch_error.provider_request_id,
        messages_count: dispatch_error.messages_count,
        duration_ms: dispatch_error.duration_ms
      )
      handle_failure_outcome!(failure_result.failure_outcome)
      raise dispatch_error.error if failure_result.failure_outcome.terminal?

      @workflow_node.reload
    rescue ProviderExecution::ExecuteRoundLoop::PromptSizeFailure => error
      fail_output_stream_if_started!(
        code: "prompt_too_large",
        message: error.message
      )
      failure_result = ProviderExecution::PersistTurnStepFailure.call(
        workflow_node: @workflow_node,
        request_context: @request_context,
        error: error,
        provider_request_id: nil,
        messages_count: error.messages_count,
        duration_ms: 0
      )
      handle_failure_outcome!(failure_result.failure_outcome)
      @workflow_node.reload
    rescue ProviderExecution::ExecuteRoundLoop::RoundLimitExceeded => error
      fail_output_stream_if_started!(
        code: "round_limit_exceeded",
        message: error.message
      )
      failure_result = ProviderExecution::PersistTurnStepFailure.call(
        workflow_node: @workflow_node,
        request_context: @request_context,
        error: error,
        provider_request_id: nil,
        messages_count: error.messages_count,
        duration_ms: 0
      )
      handle_failure_outcome!(failure_result.failure_outcome)
      raise if failure_result.failure_outcome.terminal?

      @workflow_node.reload
    rescue StaleExecutionError
      if output_stream.started?
        output_stream.fail!(code: "stale_execution", message: "provider execution result is stale")
        broadcast_workflow_node_event!(
          "runtime.workflow_node.canceled",
          state: "canceled",
          code: "stale_execution",
          error_message: "provider execution result is stale"
        )
      end
      raise
    rescue StandardError => error
      fail_output_stream_if_started!(
        code: "provider_execution_failed",
        message: error.message
      )
      raise
    end

    private

    def output_stream
      @output_stream ||= ProviderExecution::OutputStream.new(workflow_node: @workflow_node)
    end

    def normalize_messages(messages)
      Array(messages).filter_map do |message|
        candidate = message.is_a?(Hash) ? message : nil
        next if candidate.blank?

        normalized = candidate.deep_stringify_keys
        next if normalized["role"].blank? && normalized["type"].blank?

        normalized
      end
    end

    def handle_output_delta(delta)
      return if delta.blank?

      output_stream.start! unless output_stream.started?
      output_stream.push(delta, flush: true)
    end

    def finalize_output_stream!(loop_result:, result:)
      return unless streaming_output_enabled?

      if output_stream.started?
        output_stream.complete!(message: result.output_message)
        return
      end

      output_deltas = loop_result.output_deltas.presence || [result.output_message.content]
      return if output_deltas.blank?

      output_stream.start!
      output_deltas.each { |delta| output_stream.push(delta, flush: true) }
      output_stream.complete!(message: result.output_message)
    end

    def fail_output_stream_if_started!(code:, message:)
      return unless output_stream.started?

      output_stream.fail!(code:, message:)
    end

    def streaming_output_enabled?
      @request_context.capabilities.fetch("streaming", false) == true
    end

    def claim_running!
      @workflow_node.with_lock do
        now = Time.current

        @workflow_node.reload
        raise StaleExecutionError, "provider execution result is stale" if @workflow_node.terminal? || @workflow_node.running?
        unless @workflow_node.pending? || @workflow_node.queued?
          raise_invalid!(@workflow_node, :lifecycle_state, "must be pending or queued before provider execution")
        end

        @workflow_node.update!(
          lifecycle_state: "running",
          started_at: @workflow_node.started_at || now,
          finished_at: nil
        )

        WorkflowNodeEvent.create!(
          installation: @workflow_run.installation,
          workflow_run: @workflow_run,
          workflow_node: @workflow_node,
          ordinal: @workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: { "state" => "running" }
        )
      end
    end

    def handle_failure_outcome!(failure_outcome)
      if output_stream.started?
        output_stream.fail!(
          code: failure_stream_code_for(failure_outcome),
          message: failure_outcome.failure_kind.to_s.humanize
        )
      end

      event_kind = failure_outcome.terminal? ? "runtime.workflow_node.failed" : "runtime.workflow_node.waiting"
      payload = {
        "state" => failure_outcome.terminal? ? "failed" : "waiting",
        "failure_category" => failure_outcome.failure_category,
        "failure_kind" => failure_outcome.failure_kind,
        "retry_strategy" => failure_outcome.retry_strategy,
        "retry_at" => failure_outcome.next_retry_at&.iso8601,
      }.compact
      wait_reason_payload = @workflow_run.reload.wait_reason_payload.deep_stringify_keys
      payload["remediation"] = wait_reason_payload["remediation"] if wait_reason_payload["remediation"].present?
      payload["degradation"] = wait_reason_payload["degradation"] if wait_reason_payload["degradation"].present?
      broadcast_workflow_node_event!(event_kind, **payload)
    end

    def failure_stream_code_for(failure_outcome)
      return "provider_request_failed" if failure_outcome.terminal?

      "provider_request_blocked"
    end

    def broadcast_workflow_node_event!(event_kind, **payload)
      ConversationRuntime::PublishEvent.call(
        conversation: @workflow_run.conversation,
        turn: @turn,
        event_kind: event_kind,
        payload: payload.merge(
          "workflow_run_id" => @workflow_run.public_id,
          "workflow_node_id" => @workflow_node.public_id
        )
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end

    def prompt_compaction_preflight_failure
      payload = prompt_compaction_artifact_payload
      return if payload.blank?

      case payload["stop_reason"]
      when "selected_input_exceeds_hard_limit"
        ProviderExecution::ExecuteRoundLoop::PromptTooLargeForRetry.new(
          messages_count: @messages.length,
          selected_input_message_id: payload["selected_input_message_id"].presence || @workflow_run.execution_snapshot.selected_input_message_id
        )
      when "hard_limit_after_compaction"
        ProviderExecution::ExecuteRoundLoop::ContextWindowExceededAfterCompaction.new(
          messages_count: @messages.length,
          selected_input_message_id: payload["selected_input_message_id"].presence || @workflow_run.execution_snapshot.selected_input_message_id
        )
      end
    end

    def prompt_compaction_artifact_payload
      @prompt_compaction_artifact_payload ||= begin
        metadata = @workflow_node.metadata.is_a?(Hash) ? @workflow_node.metadata.deep_stringify_keys : {}
        artifact_key = metadata["prompt_compaction_artifact_key"]
        source_node_key = metadata["prompt_compaction_source_node_key"]
        if artifact_key.blank? || source_node_key.blank?
          {}
        else
          source_node = @workflow_run.workflow_nodes.find_by(node_key: source_node_key)
          artifact = source_node && @workflow_run.workflow_artifacts.find_by(
            workflow_node: source_node,
            artifact_kind: "prompt_compaction_context",
            artifact_key: artifact_key
          )
          artifact&.payload&.deep_stringify_keys || {}
        end
      end
    end
  end
end
