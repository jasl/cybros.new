require "securerandom"

module ProviderExecution
  class ExecuteTurnStep
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

    def initialize(workflow_node:, messages:, adapter: nil, catalog: ProviderCatalog::Load.call)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
      @messages = normalize_messages(messages)
      @adapter = adapter
      @catalog = catalog
      @request_context = BuildRequestContext.call(turn: @turn, catalog: @catalog)
      @provider_request_id = SecureRandom.uuid
    end

    def call
      raise_invalid!(@workflow_node, :node_type, "must be a turn_step workflow node") unless @workflow_node.node_type == "turn_step"
      raise_invalid!(@workflow_run, :lifecycle_state, "must be active to execute provider work") unless @workflow_run.active?
      raise_invalid!(@workflow_run, :wait_state, "must be ready to execute provider work") unless @workflow_run.ready?
      raise_invalid!(@turn, :lifecycle_state, "must be active to execute provider work") unless @turn.active?
      raise_invalid!(@workflow_node, :base, "must provide at least one provider message") if @messages.empty?
      raise_invalid!(@turn, :resolved_config_snapshot, "must use a supported provider wire API") unless @request_context.fetch("wire_api") == "chat_completions"
      raise_invalid!(@workflow_node, :base, "already has terminal execution status") if terminal_event_state.present?

      append_status_event!("running")

      started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      provider_result = build_client.chat(
        model: @request_context.fetch("api_model"),
        messages: @messages,
        max_tokens: @request_context.dig("hard_limits", "max_output_tokens"),
        **@request_context.fetch("execution_settings").symbolize_keys
      )
      duration_ms = elapsed_ms_since(started_monotonic)

      persist_success!(provider_result: provider_result, duration_ms: duration_ms)
    rescue SimpleInference::Error => error
      duration_ms = elapsed_ms_since(started_monotonic)
      persist_failure!(error: error, duration_ms: duration_ms)
      raise
    end

    private

    def build_client
      provider_definition = @catalog.provider(@request_context.fetch("provider_handle"))

      SimpleInference::Client.new(
        base_url: provider_definition.fetch(:base_url),
        api_key: credential_secret_for(provider_definition),
        headers: provider_definition.fetch(:headers, {}),
        adapter: @adapter || SimpleInference::HTTPAdapters::HTTPX.new
      )
    end

    def credential_secret_for(provider_definition)
      return nil unless provider_definition.fetch(:requires_credential)

      ProviderCredential.find_by!(
        installation: @workflow_run.installation,
        provider_handle: @request_context.fetch("provider_handle"),
        credential_kind: provider_definition.fetch(:credential_kind)
      ).secret
    end

    def persist_success!(provider_result:, duration_ms:)
      usage = normalize_usage(provider_result.usage)
      usage_evaluation = evaluate_usage(usage)

      ApplicationRecord.transaction do
        output_message = AgentMessage.create!(
          installation: @turn.installation,
          conversation: @turn.conversation,
          turn: @turn,
          role: "agent",
          slot: "output",
          variant_index: @turn.messages.where(slot: "output").maximum(:variant_index).to_i + 1,
          content: provider_result.content.to_s
        )
        usage_event = ProviderUsage::RecordEvent.call(
          installation: @workflow_run.installation,
          user: @workflow_run.workspace.user,
          workspace: @workflow_run.workspace,
          conversation_id: @workflow_run.conversation_id,
          turn_id: @workflow_run.turn_id,
          workflow_node_key: @workflow_node.node_key,
          agent_installation: @turn.agent_deployment.agent_installation,
          agent_deployment: @turn.agent_deployment,
          provider_handle: @request_context.fetch("provider_handle"),
          model_ref: @request_context.fetch("model_ref"),
          operation_kind: "text_generation",
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"],
          latency_ms: duration_ms,
          success: true,
          entitlement_window_key: @turn.resolved_model_selection_snapshot["entitlement_key"]
        )
        profiling_fact = ExecutionProfiling::RecordFact.call(
          installation: @workflow_run.installation,
          user: @workflow_run.workspace.user,
          workspace: @workflow_run.workspace,
          conversation_id: @workflow_run.conversation_id,
          turn_id: @workflow_run.turn_id,
          workflow_node_key: @workflow_node.node_key,
          fact_kind: "provider_request",
          fact_key: @workflow_node.node_key,
          count_value: @messages.length,
          duration_ms: duration_ms,
          success: true,
          metadata: profiling_metadata(
            provider_result: provider_result,
            usage_evaluation: usage_evaluation
          )
        )

        @turn.update!(
          selected_output_message: output_message,
          lifecycle_state: "completed"
        )
        @workflow_run.update!(lifecycle_state: "completed")
        append_status_event!(
          "completed",
          output_message_id: output_message.public_id,
          provider_request_id: provider_request_id_for(provider_result),
          usage_event_id: usage_event.id,
          execution_profile_fact_id: profiling_fact.id
        )

        Result.new(
          workflow_run: @workflow_run,
          workflow_node: @workflow_node,
          output_message: output_message,
          usage_event: usage_event,
          execution_profile_fact: profiling_fact
        )
      end
    end

    def persist_failure!(error:, duration_ms:)
      ApplicationRecord.transaction do
        profiling_fact = ExecutionProfiling::RecordFact.call(
          installation: @workflow_run.installation,
          user: @workflow_run.workspace.user,
          workspace: @workflow_run.workspace,
          conversation_id: @workflow_run.conversation_id,
          turn_id: @workflow_run.turn_id,
          workflow_node_key: @workflow_node.node_key,
          fact_kind: "provider_request",
          fact_key: @workflow_node.node_key,
          count_value: @messages.length,
          duration_ms: duration_ms,
          success: false,
          metadata: {
            "provider_request_id" => @provider_request_id,
            "provider_handle" => @request_context.fetch("provider_handle"),
            "model_ref" => @request_context.fetch("model_ref"),
            "wire_api" => @request_context.fetch("wire_api"),
            "error_class" => error.class.name,
            "error_message" => error.message,
          }
        )

        @turn.update!(lifecycle_state: "failed")
        @workflow_run.update!(lifecycle_state: "failed")
        append_status_event!(
          "failed",
          provider_request_id: @provider_request_id,
          execution_profile_fact_id: profiling_fact.id,
          error_class: error.class.name,
          error_message: error.message
        )
      end
    end

    def profiling_metadata(provider_result:, usage_evaluation:)
      {
        "provider_request_id" => provider_request_id_for(provider_result),
        "provider_handle" => @request_context.fetch("provider_handle"),
        "model_ref" => @request_context.fetch("model_ref"),
        "api_model" => @request_context.fetch("api_model"),
        "wire_api" => @request_context.fetch("wire_api"),
        "execution_settings" => @request_context.fetch("execution_settings"),
        "hard_limits" => @request_context.fetch("hard_limits"),
        "advisory_hints" => @request_context.fetch("advisory_hints"),
        "usage_evaluation" => usage_evaluation,
      }
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
      threshold = @request_context.dig("advisory_hints", "recommended_compaction_threshold")

      {
        "source" => "provider",
        "input_tokens" => usage["input_tokens"],
        "output_tokens" => usage["output_tokens"],
        "total_tokens" => total_tokens,
        "recommended_compaction_threshold" => threshold,
        "threshold_crossed" => threshold.present? && total_tokens >= threshold,
      }.compact
    end

    def provider_request_id_for(provider_result)
      provider_result.response.headers["x-request-id"] ||
        provider_result.response.body&.fetch("id", nil) ||
        @provider_request_id
    end

    def append_status_event!(state, **payload)
      @workflow_node.with_lock do
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

    def terminal_event_state
      @workflow_node.workflow_node_events
        .where(event_kind: "status")
        .order(ordinal: :desc)
        .limit(1)
        .pick(Arel.sql("payload ->> 'state'"))
        .presence_in(%w[completed failed canceled])
    end

    def elapsed_ms_since(started_monotonic)
      return 0 if started_monotonic.nil?

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_monotonic) * 1000).round
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
