module Workflows
  class ExecuteNode
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, messages: nil, adapter: nil)
      @workflow_node = workflow_node
      @messages = messages
      @adapter = adapter
    end

    def call
      current_node = WorkflowNode.find_by_public_id!(@workflow_node.public_id)
      return current_node if current_node.terminal? || current_node.running?

      case current_node.node_type
      when "turn_step"
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: current_node,
          messages: @messages || default_messages(current_node),
          adapter: @adapter
        )
      when "turn_root", "barrier_join"
        complete_coordination_node!(current_node)
      else
        raise ArgumentError, "unsupported workflow node type #{current_node.node_type}"
      end
    end

    private

    def default_messages(workflow_node)
      workflow_node.workflow_run.execution_snapshot.context_messages.map { |entry| entry.slice("role", "content") }
    end

    def complete_coordination_node!(workflow_node)
      now = Time.current

      workflow_node.with_lock do
        workflow_node.reload
        return workflow_node if workflow_node.terminal?

        workflow_node.update!(
          lifecycle_state: "completed",
          started_at: workflow_node.started_at || now,
          finished_at: now
        )
        WorkflowNodeEvent.create!(
          installation: workflow_node.installation,
          workflow_run: workflow_node.workflow_run,
          workflow_node: workflow_node,
          ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
          event_kind: "status",
          payload: {
            "state" => "completed",
          }
        )
      end

      Workflows::RefreshRunLifecycle.call(workflow_run: workflow_node.workflow_run)
      Workflows::DispatchRunnableNodes.call(workflow_run: workflow_node.workflow_run)
      workflow_node
    end
  end
end
