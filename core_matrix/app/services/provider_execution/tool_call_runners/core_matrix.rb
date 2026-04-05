module ProviderExecution
  module ToolCallRunners
    class CoreMatrix
      def self.call(...)
        new(...).call
      end

      def initialize(workflow_node:, tool_call:, binding:, **)
        @workflow_node = workflow_node
        @tool_call = tool_call
        @binding = binding
      end

      def call
        provision = ToolInvocations::Provision.call(
          tool_binding: @binding,
          request_payload: {
            "arguments" => @tool_call.fetch("arguments", {}),
          },
          idempotency_key: @tool_call.fetch("call_id"),
          provider_format: @tool_call["provider_format"]
        )
        invocation = provision.tool_invocation
        return existing_result(invocation) unless provision.created

        begin
          result = ProviderExecution::ExecuteCoreMatrixTool.call(
            workflow_node: @workflow_node,
            tool_call: @tool_call
          )
          ToolInvocations::Complete.call(
            tool_invocation: invocation,
            response_payload: result
          )
          ProviderExecution::RouteToolCall::Result.new(
            tool_call: @tool_call,
            tool_binding: @binding,
            tool_invocation: invocation.reload,
            result: result
          )
        rescue StandardError => error
          ToolInvocations::Fail.call(
            tool_invocation: invocation,
            error_payload: execution_error_payload_for(error)
          )
          raise
        end
      end

      private

      def existing_result(invocation)
        ProviderExecution::RouteToolCall::Result.new(
          tool_call: @tool_call,
          tool_binding: @binding,
          tool_invocation: invocation,
          result: invocation.succeeded? ? invocation.response_payload : { "error" => invocation.error_payload }
        )
      end

      def execution_error_payload_for(error)
        classification =
          case error
          when ActiveRecord::RecordNotFound, KeyError
            "semantic"
          when ActiveRecord::RecordInvalid
            "authorization"
          else
            "runtime"
          end

        {
          "classification" => classification,
          "code" => "tool_execution_failed",
          "message" => error.message,
          "retryable" => false,
        }
      end
    end
  end
end
