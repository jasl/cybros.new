module ProviderExecution
  class RouteToolCall
    Result = Struct.new(:tool_call, :tool_binding, :tool_invocation, :result, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_call:, round_bindings:, program_exchange: nil)
      @workflow_node = workflow_node
      @tool_call = tool_call.deep_stringify_keys
      @round_bindings = Array(round_bindings)
      @program_exchange = program_exchange || ProviderExecution::ProgramMailboxExchange.new(agent_program_version: workflow_node.turn.agent_program_version)
    end

    def call
      binding = find_binding!
      ProviderExecution::ToolCallRunners
        .fetch!(binding.tool_implementation.implementation_source.source_kind)
        .call(
          workflow_node: @workflow_node,
          tool_call: @tool_call,
          binding: binding,
          program_exchange: @program_exchange
        )
    end

    private

    def find_binding!
      @round_bindings.find { |binding| binding.tool_definition.tool_name == @tool_call.fetch("tool_name") } ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find ToolBinding for #{@tool_call.fetch("tool_name")}")
    end
  end
end
