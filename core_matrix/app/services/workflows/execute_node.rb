module Workflows
  class ExecuteNode
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, messages: nil, adapter: nil, agent_request_exchange: nil, request_preparation_exchange: nil, execution_runtime_exchange: nil, catalog: nil)
      @workflow_node = workflow_node
      @messages = messages
      @adapter = adapter
      @agent_request_exchange = agent_request_exchange
      @request_preparation_exchange = request_preparation_exchange
      @execution_runtime_exchange = execution_runtime_exchange
      @catalog = catalog
    end

    def call
      current_node = WorkflowNode.find_by_public_id!(@workflow_node.public_id)
      return current_node if current_node.workflow_run.waiting?
      return current_node if current_node.terminal? || current_node.running?

      case current_node.node_type
      when "turn_step"
        ProviderExecution::ExecuteTurnStep.call(
          workflow_node: current_node,
          messages: @messages || default_messages(current_node),
          adapter: @adapter,
          agent_request_exchange: @agent_request_exchange,
          request_preparation_exchange: @request_preparation_exchange,
          catalog: @catalog
        )
      when "prompt_compaction"
        ProviderExecution::ExecutePromptCompactionNode.call(
          workflow_node: current_node,
          request_preparation_exchange: @request_preparation_exchange
        )
      when "tool_call"
        ProviderExecution::ExecuteToolNode.call(
          workflow_node: current_node,
          agent_request_exchange: @agent_request_exchange,
          execution_runtime_exchange: @execution_runtime_exchange
        )
      when "turn_root", "barrier_join"
        complete_coordination_node!(current_node)
      else
        raise ArgumentError, "unsupported workflow node type #{current_node.node_type}"
      end
    end

    private

    def default_messages(workflow_node)
      compacted_messages = ProviderExecution::LoadPromptCompactionContext.call(workflow_node:)
      return compacted_messages if compacted_messages.present?

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
