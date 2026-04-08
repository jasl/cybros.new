module Fenix
  module Runtime
    module Assignments
      class ToolInvocationPayloads
        def self.current(tool_call:, tool_invocation:, command_run:)
          {
            "tool_invocation_id" => tool_invocation.fetch("tool_invocation_id"),
            "command_run_id" => command_run&.fetch("command_run_id"),
            "call_id" => tool_call.fetch("call_id"),
            "tool_name" => tool_call.fetch("tool_name"),
            "request_payload" => tool_call.except("call_id"),
          }.compact
        end

        def self.started(current_tool_invocation)
          {
            "event" => "started",
            "tool_invocation_id" => current_tool_invocation.fetch("tool_invocation_id"),
            "command_run_id" => current_tool_invocation["command_run_id"],
            "call_id" => current_tool_invocation.fetch("call_id"),
            "tool_name" => current_tool_invocation.fetch("tool_name"),
            "request_payload" => current_tool_invocation.fetch("request_payload"),
          }.compact
        end

        def self.completed(current_tool_invocation:, response_payload:)
          {
            "event" => "completed",
            "tool_invocation_id" => current_tool_invocation.fetch("tool_invocation_id"),
            "command_run_id" => current_tool_invocation["command_run_id"],
            "call_id" => current_tool_invocation.fetch("call_id"),
            "tool_name" => current_tool_invocation.fetch("tool_name"),
            "response_payload" => response_payload,
          }.compact
        end

        def self.failed(current_tool_invocation:, error:)
          {
            "event" => "failed",
            "call_id" => current_tool_invocation.fetch("call_id"),
            "tool_name" => current_tool_invocation.fetch("tool_name"),
            "request_payload" => current_tool_invocation.fetch("request_payload"),
            "error_payload" => Fenix::Runtime::ProgramToolExecutor.error_payload_for(error),
          }.merge(
            {
              "tool_invocation_id" => current_tool_invocation["tool_invocation_id"],
              "command_run_id" => current_tool_invocation["command_run_id"],
            }.compact
          )
        end
      end
    end
  end
end
