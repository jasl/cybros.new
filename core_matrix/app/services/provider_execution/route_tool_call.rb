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
      @program_exchange = program_exchange || ProviderExecution::ProgramMailboxExchange.new(agent_deployment: workflow_node.turn.agent_deployment)
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
      when "agent", "kernel", "execution_environment"
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

        response = @program_exchange.execute_program_tool(payload: execute_program_tool_payload(invocation:))
        if response.fetch("status") == "ok"
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
            error_payload: response.fetch("failure"),
            metadata: tool_execution_metadata(response)
          )
          Result.new(
            tool_call: @tool_call,
            tool_binding: binding,
            tool_invocation: invocation.reload,
            result: { "error" => response.fetch("failure") }
          )
        end
      when "core_matrix"
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

        begin
          result = ProviderExecution::ExecuteCoreMatrixTool.call(
            workflow_node: @workflow_node,
            tool_call: @tool_call
          )
          ToolInvocations::Complete.call(
            tool_invocation: invocation,
            response_payload: result
          )
          Result.new(
            tool_call: @tool_call,
            tool_binding: binding,
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
      capability_projection = @workflow_node.workflow_run.execution_snapshot.capability_projection
      tool_surface = capability_projection.fetch("tool_surface", []).select do |entry|
        entry.fetch("tool_name") == @tool_call.fetch("tool_name")
      end

      {
        "protocol_version" => "agent-program/2026-04-01",
        "request_kind" => "execute_program_tool",
        "task" => {
          "workflow_node_id" => @workflow_node.public_id,
          "conversation_id" => @workflow_node.conversation.public_id,
          "turn_id" => @workflow_node.turn.public_id,
          "kind" => "turn_step",
        },
        "capability_projection" => capability_projection.merge(
          "tool_surface" => tool_surface
        ),
        "provider_context" => {
          "provider_execution" => @workflow_node.workflow_run.provider_execution,
          "model_context" => @workflow_node.workflow_run.model_context,
        },
        "runtime_context" => {
          "runtime_plane" => "agent",
          "logical_work_id" => "program-tool:#{@workflow_node.public_id}:#{@tool_call.fetch("call_id")}",
          "attempt_no" => 1,
          "deployment_public_id" => @workflow_node.turn.agent_deployment.public_id,
        },
        "program_tool_call" => {
          "call_id" => @tool_call.fetch("call_id"),
          "tool_name" => @tool_call.fetch("tool_name"),
          "arguments" => @tool_call.fetch("arguments", {}),
        },
        "runtime_resource_refs" => {
          "tool_invocation" => {
            "tool_invocation_id" => invocation.public_id,
          },
          "command_run" => nil,
          "process_run" => nil,
        },
      }.compact
    end

    def tool_execution_metadata(response)
      {
        "fenix" => {
          "summary_artifacts" => response["summary_artifacts"],
          "output_chunks" => response["output_chunks"],
        }.compact,
      }
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
