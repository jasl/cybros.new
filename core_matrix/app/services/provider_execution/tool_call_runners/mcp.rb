module ProviderExecution
  module ToolCallRunners
    class MCP
      def self.call(...)
        new(...).call
      end

      def initialize(tool_call:, binding:, **)
        @tool_call = tool_call
        @binding = binding
      end

      def call
        invocation = ::MCP::InvokeTool.call(
          tool_binding: @binding,
          request_payload: {
            "arguments" => @tool_call.fetch("arguments", {}),
          }
        )

        ProviderExecution::RouteToolCall::Result.new(
          tool_call: @tool_call,
          tool_binding: @binding,
          tool_invocation: invocation,
          result: invocation.succeeded? ? invocation.response_payload : { "error" => invocation.error_payload }
        )
      end
    end
  end
end
