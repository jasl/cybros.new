module ProviderExecution
  class RouteToolCall
    Result = Struct.new(:tool_call, :tool_binding, :tool_invocation, :result, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_call:, round_bindings:, program_client: nil)
      @workflow_node = workflow_node
      @tool_call = tool_call.deep_stringify_keys
      @round_bindings = Array(round_bindings)
      @program_client = program_client || ProviderExecution::FenixProgramClient.new(agent_deployment: workflow_node.turn.agent_deployment)
    end

    def call
      binding = find_binding!

      case binding.tool_implementation.implementation_source.source_kind
      when "mcp"
        invocation = MCP::InvokeTool.call(
          tool_binding: binding,
          request_payload: {
            "arguments" => @tool_call.fetch("arguments", {}),
          }
        )
        Result.new(
          tool_call: @tool_call,
          tool_binding: binding,
          tool_invocation: invocation,
          result: invocation.succeeded? ? invocation.response_payload : { "error" => invocation.error_payload }
        )
      when "agent", "kernel"
        provision = ToolInvocations::Provision.call(
          tool_binding: binding,
          request_payload: {
            "arguments" => @tool_call.fetch("arguments", {}),
          },
          idempotency_key: @tool_call.fetch("call_id"),
          metadata: {
            "provider_format" => @tool_call["provider_format"],
          }.compact
        )
        invocation = provision.tool_invocation
        return existing_result(binding:, invocation:) unless provision.created

        response = @program_client.execute_program_tool(body: execute_program_tool_payload(invocation:))
        if response.fetch("status") == "completed"
          ToolInvocations::Complete.call(
            tool_invocation: invocation,
            response_payload: response.fetch("result"),
            metadata: tool_execution_metadata(response)
          )
          Result.new(
            tool_call: @tool_call,
            tool_binding: binding,
            tool_invocation: invocation.reload,
            result: response.fetch("result")
          )
        else
          ToolInvocations::Fail.call(
            tool_invocation: invocation,
            error_payload: response.fetch("error"),
            metadata: tool_execution_metadata(response)
          )
          Result.new(
            tool_call: @tool_call,
            tool_binding: binding,
            tool_invocation: invocation.reload,
            result: { "error" => response.fetch("error") }
          )
        end
      else
        raise ArgumentError, "unsupported tool implementation source #{binding.tool_implementation.implementation_source.source_kind}"
      end
    end

    private

    def find_binding!
      @round_bindings.find { |binding| binding.tool_definition.tool_name == @tool_call.fetch("tool_name") } ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find ToolBinding for #{@tool_call.fetch("tool_name")}")
    end

    def existing_result(binding:, invocation:)
      Result.new(
        tool_call: @tool_call,
        tool_binding: binding,
        tool_invocation: invocation,
        result: invocation.succeeded? ? invocation.response_payload : { "error" => invocation.error_payload }
      )
    end

    def execute_program_tool_payload(invocation:)
      {
        "conversation_id" => @workflow_node.conversation.public_id,
        "turn_id" => @workflow_node.turn.public_id,
        "workflow_node_id" => @workflow_node.public_id,
        "agent_task_run_id" => invocation.agent_task_run&.public_id,
        "tool_call_id" => @tool_call.fetch("call_id"),
        "tool_name" => @tool_call.fetch("tool_name"),
        "arguments" => @tool_call.fetch("arguments", {}),
        "agent_context" => @workflow_node.workflow_run.execution_snapshot.agent_context,
        "provider_execution" => @workflow_node.workflow_run.provider_execution,
        "model_context" => @workflow_node.workflow_run.model_context,
        "tool_invocation" => {
          "tool_invocation_id" => invocation.public_id,
        },
      }.compact
    end

    def tool_execution_metadata(response)
      {
        "fenix" => {
          "summary" => response["summary"],
          "output_chunks" => response["output_chunks"],
        }.compact,
      }
    end
  end
end
