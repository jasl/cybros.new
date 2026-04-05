module ProviderExecution
  class LoadPriorToolResults
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:)
      @workflow_node = workflow_node
    end

    def call
      ordered_tool_nodes.map do |node|
        tool_call = node.tool_call_payload&.deep_stringify_keys ||
          raise(ActiveRecord::RecordNotFound, "missing tool call payload for #{node.node_key}")
        invocation = node.tool_invocations.order(:created_at).last ||
          raise(ActiveRecord::RecordNotFound, "missing ToolInvocation for #{node.node_key}")

        {
          "tool_call_id" => tool_call.fetch("call_id"),
          "call_id" => tool_call.fetch("call_id"),
          "tool_name" => tool_call.fetch("tool_name"),
          "arguments" => tool_call.fetch("arguments", {}),
          "provider_format" => tool_call["provider_format"],
          "provider_item_id" => tool_call["provider_item_id"],
          "result" => invocation.succeeded? ? invocation.response_payload : { "error" => invocation.error_payload },
        }.compact
      end
    end

    private

    def ordered_tool_nodes
      node_keys = Array(@workflow_node.prior_tool_node_keys)
      return [] if node_keys.empty?

      nodes_by_key = @workflow_node.workflow_run.workflow_nodes.where(node_key: node_keys).includes(:tool_invocations).index_by(&:node_key)

      node_keys.map do |node_key|
        nodes_by_key.fetch(node_key) do
          raise ActiveRecord::RecordNotFound, "missing WorkflowNode #{node_key}"
        end
      end
    end
  end
end
