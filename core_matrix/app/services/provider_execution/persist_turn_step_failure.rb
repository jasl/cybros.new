module ProviderExecution
  class PersistTurnStepFailure
    Result = Struct.new(:profiling_fact, :failure_outcome, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, request_context:, error:, provider_request_id:, messages_count:, duration_ms:)
      @workflow_node = workflow_node
      @request_context = ProviderRequestContext.wrap(request_context)
      @error = error
      @provider_request_id = provider_request_id
      @messages_count = messages_count
      @duration_ms = duration_ms
      @workflow_run = workflow_node.workflow_run
      @turn = workflow_node.turn
    end

    def call
      profiling_fact = nil
      failure_outcome = nil
      classification = ProviderExecution::FailureClassification.call(error: @error)

      ApplicationRecord.transaction do
        ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: @workflow_node) do |current_node, current_workflow_run, current_turn|
          profiling_fact = ExecutionProfiling::RecordProviderRequestFact.call(
            workflow_run: current_workflow_run,
            workflow_node_key: current_node.node_key,
            request_context: @request_context,
            provider_request_id: @provider_request_id,
            messages_count: @messages_count,
            duration_ms: @duration_ms,
            success: false,
            error: @error
          )

          failure_outcome = Workflows::BlockNodeForFailure.call(
            workflow_node: current_node,
            failure_category: classification.failure_category,
            failure_kind: classification.failure_kind,
            retry_strategy: classification.retry_strategy,
            max_auto_retries: classification.max_auto_retries,
            next_retry_at: classification.next_retry_at,
            last_error_summary: classification.last_error_summary,
            metadata: failure_metadata(profiling_fact),
          )
        end
      end

      Result.new(profiling_fact: profiling_fact, failure_outcome: failure_outcome)
    end

    private

    def failure_metadata(profiling_fact)
      {
        "provider_request_id" => @provider_request_id,
        "provider_handle" => @request_context.provider_handle,
        "model_ref" => @request_context.model_ref,
        "wire_api" => @request_context.wire_api,
        "execution_profile_fact_id" => profiling_fact.id,
        "error_class" => @error.class.name,
        "remediation" => remediation_metadata,
        "degradation" => degradation_metadata,
      }.compact
    end

    def remediation_metadata
      failure_scope = prompt_failure_scope
      return if failure_scope.blank?

      {
        "tail_input_editable" => failure_scope == "current_input",
        "user_must_send_new_message" => failure_scope != "current_input",
        "failure_scope" => failure_scope,
        "current_message_only" => failure_scope == "current_input",
        "selected_input_message_id" => selected_input_message_public_id,
      }.compact
    end

    def degradation_metadata
      metadata = prompt_compaction_artifact_payload.slice("source", "fallback_used", "runtime_failure_code").compact
      return if metadata.blank?

      metadata
    end

    def prompt_failure_scope
      return @error.failure_scope if @error.respond_to?(:failure_scope)

      artifact_scope = prompt_compaction_artifact_payload["failure_scope"].presence
      return artifact_scope if artifact_scope.present?

      return "full_context" if provider_prompt_overflow?

      nil
    end

    def selected_input_message_public_id
      return @error.selected_input_message_id if @error.respond_to?(:selected_input_message_id) && @error.selected_input_message_id.present?

      prompt_compaction_artifact_payload["selected_input_message_id"].presence ||
        @workflow_run.execution_snapshot.selected_input_message_id
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
          if source_node.blank?
            {}
          else
            artifact = @workflow_run.workflow_artifacts.find_by(
              workflow_node: source_node,
              artifact_kind: "prompt_compaction_context",
              artifact_key: artifact_key
            )
            artifact&.payload&.deep_stringify_keys || {}
          end
        end
      end
    end

    def provider_prompt_overflow?
      return false unless @error.is_a?(SimpleInference::HTTPError)

      body_text = [@error.message, @error.raw_body, @error.body].compact.join(" ").downcase

      ProviderExecution::PromptOverflowDetection.matches?(status: @error.status, body_text: body_text)
    end
  end
end
