module ExecutionProfiling
  class RecordProviderRequestFact
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, workflow_node_key:, request_context:, provider_request_id:, messages_count:, duration_ms:, success:, usage: nil, error: nil, occurred_at: Time.current)
      @workflow_run = workflow_run
      @workflow_node_key = workflow_node_key
      @request_context = ProviderRequestContext.wrap(request_context)
      @provider_request_id = provider_request_id
      @messages_count = messages_count
      @duration_ms = duration_ms
      @success = success
      @usage = normalize_usage(usage)
      @error = error
      @occurred_at = occurred_at
    end

    def call
      ExecutionProfiling::RecordFact.call(
        installation: @workflow_run.installation,
        user: @workflow_run.workspace.user,
        workspace: @workflow_run.workspace,
        conversation_id: @workflow_run.conversation_id,
        turn_id: @workflow_run.turn_id,
        workflow_node_key: @workflow_node_key,
        fact_kind: "provider_request",
        fact_key: @workflow_node_key,
        provider_request_id: @provider_request_id,
        provider_handle: @request_context.provider_handle,
        model_ref: @request_context.model_ref,
        api_model: @request_context.api_model,
        wire_api: @request_context.wire_api,
        total_tokens: usage_summary["total_tokens"],
        recommended_compaction_threshold: usage_summary["recommended_compaction_threshold"],
        threshold_crossed: usage_summary["threshold_crossed"],
        error_class: @error&.class&.name,
        error_message: @error&.message,
        count_value: @messages_count,
        duration_ms: @duration_ms,
        success: @success,
        metadata: {},
        occurred_at: @occurred_at
      )
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

    def usage_summary
      @usage_summary ||= begin
        threshold = @request_context.advisory_hints["recommended_compaction_threshold"]
        total_tokens = @usage["total_tokens"]
        total_tokens ||= @usage["input_tokens"].to_i + @usage["output_tokens"].to_i if @usage.present?

        {
          "total_tokens" => total_tokens,
          "recommended_compaction_threshold" => threshold,
          "threshold_crossed" => threshold.present? && total_tokens.present? && total_tokens >= threshold,
        }.compact
      end
    end
  end
end
