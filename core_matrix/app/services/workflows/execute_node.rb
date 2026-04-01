module Workflows
  class ExecuteNode
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, messages: nil, adapter: nil, program_exchange: nil)
      @workflow_node = workflow_node
      @messages = messages
      @adapter = adapter
      @program_exchange = program_exchange
    end

    def call
      current_node = WorkflowNode.find_by_public_id!(@workflow_node.public_id)
      return current_node if current_node.terminal? || current_node.running?

      case current_node.node_type
      when "turn_step"
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: current_node,
          messages: @messages || default_messages(current_node),
          adapter: @adapter,
          program_exchange: @program_exchange
        )
      when "tool_call"
        ProviderExecution::ExecuteToolNode.call(
          workflow_node: current_node,
          program_exchange: @program_exchange
        )
      when "turn_root", "barrier_join"
        complete_coordination_node!(current_node)
      else
        raise ArgumentError, "unsupported workflow node type #{current_node.node_type}"
      end
    end

    private

    def default_messages(workflow_node)
      workflow_node.workflow_run.execution_snapshot.conversation_projection.fetch("messages", []).map { |entry| entry.slice("role", "content") }
    end

    def complete_coordination_node!(workflow_node)
      workflow_node = Workflows::CompleteNode.call(workflow_node: workflow_node)
      Workflows::RefreshRunLifecycle.call(workflow_run: workflow_node.workflow_run)
      Workflows::DispatchRunnableNodes.call(workflow_run: workflow_node.workflow_run)
      workflow_node
    end
  end
end
