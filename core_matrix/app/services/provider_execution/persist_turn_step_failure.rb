module ProviderExecution
  class PersistTurnStepFailure
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
      ApplicationRecord.transaction do
        ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: @workflow_node) do |current_node, current_workflow_run, current_turn|
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
            success: false,
            metadata: {
              "provider_request_id" => @provider_request_id,
              "provider_handle" => @request_context.provider_handle,
              "model_ref" => @request_context.model_ref,
              "wire_api" => @request_context.wire_api,
              "error_class" => @error.class.name,
              "error_message" => @error.message,
            }
          )

          current_turn.update!(lifecycle_state: "failed")
          current_workflow_run.update!(lifecycle_state: "failed")
          append_status_event!(
            workflow_node: current_node,
            workflow_run: current_workflow_run,
            state: "failed",
            provider_request_id: @provider_request_id,
            execution_profile_fact_id: profiling_fact.id,
            error_class: @error.class.name,
            error_message: @error.message
          )

          return profiling_fact
        end
      end
    end

    private

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
