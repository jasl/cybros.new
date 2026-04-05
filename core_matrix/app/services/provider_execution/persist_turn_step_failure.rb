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
            metadata: {
              "provider_request_id" => @provider_request_id,
              "provider_handle" => @request_context.provider_handle,
              "model_ref" => @request_context.model_ref,
              "wire_api" => @request_context.wire_api,
              "execution_profile_fact_id" => profiling_fact.id,
              "error_class" => @error.class.name,
            }
          )
        end
      end

      Result.new(profiling_fact: profiling_fact, failure_outcome: failure_outcome)
    end
  end
end
