require "securerandom"

module ProviderExecution
  class ExecuteTurnStep
    StaleExecutionError = ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError
    Result = ProviderExecution::PersistTurnStepSuccess::Result

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, messages:, adapter: nil, catalog: nil, effective_catalog: nil, program_exchange: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
      @messages = normalize_messages(messages)
      @adapter = adapter
      @program_exchange = program_exchange
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
      loop_result = ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: @workflow_node,
        transcript: @messages,
        adapter: @adapter,
        effective_catalog: @effective_catalog,
        program_exchange: @program_exchange
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
        output_stream.start!
        output_deltas = loop_result.output_deltas.presence || [result.output_message.content]
        output_deltas.each { |delta| output_stream.push(delta) }
        output_stream.complete!(message: result.output_message)
        broadcast_workflow_node_event!(
          "runtime.workflow_node.completed",
          state: "completed",
          provider_request_id: loop_result.dispatch_result.provider_request_id,
          output_message_id: result.output_message.public_id
        )
        result
      else
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
    rescue ProviderExecution::ProviderRequestGovernor::AdmissionRefused => error
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
    rescue ProviderExecution::ExecuteRoundLoop::RoundLimitExceeded => error
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
    end

    private

    def output_stream
      @output_stream ||= ProviderExecution::OutputStream.new(workflow_node: @workflow_node)
    end

    def normalize_messages(messages)
      Array(messages).filter_map do |message|
        candidate = message.is_a?(Hash) ? message : nil
        next if candidate.blank?

        {
          "role" => candidate["role"] || candidate[:role],
          "content" => candidate["content"] || candidate[:content],
        }.compact
      end
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
      broadcast_workflow_node_event!(event_kind, **payload)
    end

    def failure_stream_code_for(failure_outcome)
      return "provider_request_failed" if failure_outcome.terminal?

      "provider_request_blocked"
    end

    def broadcast_workflow_node_event!(event_kind, **payload)
      ConversationRuntime::Broadcast.call(
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
  end
end
