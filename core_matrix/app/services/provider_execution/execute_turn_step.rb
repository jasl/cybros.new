require "securerandom"

module ProviderExecution
  class ExecuteTurnStep
    StaleExecutionError = ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError
    Result = ProviderExecution::PersistTurnStepSuccess::Result

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, messages:, adapter: nil, catalog: nil, effective_catalog: nil)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
      @messages = normalize_messages(messages)
      @adapter = adapter
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
      raise_invalid!(@turn, :resolved_config_snapshot, "must use a supported provider wire API") unless @request_context.wire_api == "chat_completions"
      raise_invalid!(@workflow_node, :base, "already has terminal execution status") if @workflow_node.terminal?
      unless @workflow_node.pending? || @workflow_node.queued? || @workflow_node.running?
        raise_invalid!(@workflow_node, :lifecycle_state, "must be pending or queued before provider execution")
      end

      append_status_event!("running")

      dispatch_result = ProviderExecution::DispatchRequest.call(
        workflow_run: @workflow_run,
        request_context: @request_context,
        messages: @messages,
        adapter: @adapter,
        effective_catalog: @effective_catalog,
        provider_request_id: @provider_request_id
      )

      ProviderExecution::PersistTurnStepSuccess.call(
        workflow_node: @workflow_node,
        request_context: @request_context,
        provider_result: dispatch_result.provider_result,
        provider_request_id: dispatch_result.provider_request_id,
        messages_count: @messages.length,
        duration_ms: dispatch_result.duration_ms
      )
    rescue ProviderExecution::DispatchRequest::RequestFailed => dispatch_error
      ProviderExecution::PersistTurnStepFailure.call(
        workflow_node: @workflow_node,
        request_context: @request_context,
        error: dispatch_error.error,
        provider_request_id: dispatch_error.provider_request_id,
        messages_count: @messages.length,
        duration_ms: dispatch_error.duration_ms
      )
      raise dispatch_error.error
    end

    private

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

    def append_status_event!(state, **payload)
      @workflow_node.with_lock do
        now = Time.current

        @workflow_node.reload
        if state == "running"
          @workflow_node.update!(
            lifecycle_state: "running",
            started_at: @workflow_node.started_at || now,
            finished_at: nil
          )
        elsif state.in?(%w[completed failed canceled])
          @workflow_node.update!(
            lifecycle_state: state,
            started_at: @workflow_node.started_at || now,
            finished_at: now
          )
        end

        WorkflowNodeEvent.create!(
          installation: @workflow_run.installation,
          workflow_run: @workflow_run,
          workflow_node: @workflow_node,
          ordinal: @workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: payload.merge("state" => state)
        )
      end
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
