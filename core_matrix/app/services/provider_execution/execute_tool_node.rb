module ProviderExecution
  class ExecuteToolNode
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, program_exchange: nil)
      @workflow_node = workflow_node
      @program_exchange = program_exchange
    end

    def call
      current_node = WorkflowNode.find_by_public_id!(@workflow_node.public_id)
      return current_node if current_node.terminal? || current_node.running?

      raise_invalid!(current_node, :node_type, "must be a tool_call workflow node") unless current_node.node_type == "tool_call"

      claim_running!(current_node)
      result = ProviderExecution::RouteToolCall.call(
        workflow_node: current_node,
        tool_call: current_node.metadata.fetch("tool_call"),
        round_bindings: current_node.tool_bindings.includes(tool_implementation: :implementation_source).to_a,
        program_exchange: @program_exchange
      )

      Workflows::CompleteNode.call(
        workflow_node: current_node,
        event_payload: {
          "tool_call_id" => current_node.metadata.dig("tool_call", "call_id"),
          "tool_invocation_id" => result.tool_invocation&.public_id,
        }.compact
      )
      Workflows::RefreshRunLifecycle.call(workflow_run: current_node.workflow_run)
      Workflows::DispatchRunnableNodes.call(workflow_run: current_node.workflow_run)
      result
    rescue StandardError => error
      failure_result = fail_node!(current_node || @workflow_node, error)
      raise if failure_result.terminal?

      failure_result.workflow_node
    end

    private

    def claim_running!(workflow_node)
      workflow_node.with_lock do
        workflow_node.reload
        return if workflow_node.running?
        raise_invalid!(workflow_node, :lifecycle_state, "must be pending or queued before tool execution") unless workflow_node.pending? || workflow_node.queued?

        workflow_node.update!(
          lifecycle_state: "running",
          started_at: workflow_node.started_at || Time.current,
          finished_at: nil
        )
        WorkflowNodeEvent.create!(
          installation: workflow_node.installation,
          workflow_run: workflow_node.workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: { "state" => "running" }
        )
      end
    end

    def fail_node!(workflow_node, error)
      classification = ProviderExecution::FailureClassification.call(error: error)

      Workflows::BlockNodeForFailure.call(
        workflow_node: workflow_node,
        failure_category: classification.failure_category,
        failure_kind: classification.failure_kind,
        retry_strategy: classification.retry_strategy,
        max_auto_retries: classification.max_auto_retries,
        next_retry_at: classification.next_retry_at,
        last_error_summary: classification.last_error_summary,
        metadata: {
          "error_class" => error.class.name,
        }
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
