module ProviderExecution
  class PersistTurnStepSuccess
    Result = Struct.new(
      :workflow_run,
      :workflow_node,
      :output_message,
      :usage_event,
      :execution_profile_fact,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, request_context:, provider_result:, provider_request_id:, messages_count:, duration_ms:)
      @workflow_node = workflow_node
      @request_context = ProviderRequestContext.wrap(request_context)
      @provider_result = provider_result
      @provider_request_id = provider_request_id
      @messages_count = messages_count
      @duration_ms = duration_ms
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
    end

    def call
      usage = normalize_usage(@provider_result.usage)
      usage_evaluation = evaluate_usage(usage)

      ApplicationRecord.transaction do
        ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: @workflow_node) do |current_node, current_workflow_run, current_turn|
          output_message = Turns::CreateOutputVariant.call(
            turn: current_turn,
            content: @provider_result.content.to_s,
            source_input_message: current_turn.selected_input_message
          )
          usage_event = ProviderUsage::RecordEvent.call(
            installation: current_workflow_run.installation,
            user: current_workflow_run.workspace.user,
            workspace: current_workflow_run.workspace,
            conversation_id: current_workflow_run.conversation_id,
            turn_id: current_workflow_run.turn_id,
            workflow_node_key: current_node.node_key,
            agent_installation: current_turn.agent_deployment.agent_installation,
            agent_deployment: current_turn.agent_deployment,
            provider_handle: @request_context.provider_handle,
            model_ref: @request_context.model_ref,
            operation_kind: "text_generation",
            input_tokens: usage["input_tokens"],
            output_tokens: usage["output_tokens"],
            latency_ms: @duration_ms,
            success: true,
            entitlement_window_key: current_turn.resolved_model_selection_snapshot["entitlement_key"]
          )
          profiling_fact = ExecutionProfiling::RecordFact.call(
            installation: current_workflow_run.installation,
            user: current_workflow_run.workspace.user,
            workspace: current_workflow_run.workspace,
            conversation_id: current_workflow_run.conversation_id,
            turn_id: current_workflow_run.turn_id,
            workflow_node_key: current_node.node_key,
            fact_kind: "provider_request",
            fact_key: current_node.node_key,
            count_value: @messages_count,
            duration_ms: @duration_ms,
            success: true,
            metadata: profiling_metadata(usage_evaluation)
          )

          current_turn.update!(
            selected_output_message: output_message,
            lifecycle_state: "completed"
          )
          current_workflow_run.update!(lifecycle_state: "completed")
          append_status_event!(
            workflow_node: current_node,
            workflow_run: current_workflow_run,
            state: "completed",
            output_message_id: output_message.public_id,
            provider_request_id: @provider_request_id,
            usage_event_id: usage_event.id,
            execution_profile_fact_id: profiling_fact.id
          )

          return Result.new(
            workflow_run: current_workflow_run,
            workflow_node: current_node,
            output_message: output_message,
            usage_event: usage_event,
            execution_profile_fact: profiling_fact
          )
        end
      end
    end

    private

    def normalize_usage(usage)
      payload = usage.is_a?(Hash) ? usage : {}

      {
        "input_tokens" => payload[:prompt_tokens] || payload["prompt_tokens"] || payload[:input_tokens] || payload["input_tokens"],
        "output_tokens" => payload[:completion_tokens] || payload["completion_tokens"] || payload[:output_tokens] || payload["output_tokens"],
        "total_tokens" => payload[:total_tokens] || payload["total_tokens"],
      }.compact
    end

    def evaluate_usage(usage)
      total_tokens = usage["total_tokens"] || usage["input_tokens"].to_i + usage["output_tokens"].to_i
      threshold = @request_context.advisory_hints["recommended_compaction_threshold"]

      {
        "source" => "provider",
        "input_tokens" => usage["input_tokens"],
        "output_tokens" => usage["output_tokens"],
        "total_tokens" => total_tokens,
        "recommended_compaction_threshold" => threshold,
        "threshold_crossed" => threshold.present? && total_tokens >= threshold,
      }.compact
    end

    def profiling_metadata(usage_evaluation)
      {
        "provider_request_id" => @provider_request_id,
        "provider_handle" => @request_context.provider_handle,
        "model_ref" => @request_context.model_ref,
        "api_model" => @request_context.api_model,
        "wire_api" => @request_context.wire_api,
        "execution_settings" => @request_context.execution_settings,
        "hard_limits" => @request_context.hard_limits,
        "advisory_hints" => @request_context.advisory_hints,
        "usage_evaluation" => usage_evaluation,
      }
    end

    def append_status_event!(workflow_node:, workflow_run:, state:, **payload)
      workflow_node.with_lock do
        WorkflowNodeEvent.create!(
          installation: workflow_run.installation,
          workflow_run: workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: payload.merge("state" => state)
        )
      end
    end
  end
end
