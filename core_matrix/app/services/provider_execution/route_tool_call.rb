module ProviderExecution
  class RouteToolCall
    Result = Struct.new(:tool_call, :tool_binding, :tool_invocation, :result, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_call:, round_bindings:, agent_request_exchange: nil, execution_runtime_exchange: nil)
      @workflow_node = workflow_node
      @tool_call = tool_call.deep_stringify_keys
      @round_bindings = Array(round_bindings)
      @agent_request_exchange = agent_request_exchange || ProviderExecution::AgentRequestExchange.new(agent_definition_version: workflow_node.turn.agent_definition_version)
      @execution_runtime_exchange = execution_runtime_exchange || ProviderExecution::ExecutionRuntimeExchange.new(execution_runtime: workflow_node.turn.execution_runtime)
    end

    def call
      binding = find_binding!
      ProviderExecution::ToolCallRunners
        .fetch!(binding.tool_implementation.implementation_source.source_kind)
        .call(
          workflow_node: @workflow_node,
          tool_call: @tool_call,
          binding: binding,
          agent_request_exchange: @agent_request_exchange,
          execution_runtime_exchange: @execution_runtime_exchange
        )
    end

    private

    def find_binding!
      @round_bindings.find { |binding| binding.tool_definition.tool_name == @tool_call.fetch("tool_name") } ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find ToolBinding for #{@tool_call.fetch("tool_name")}")
    end
  end
end
