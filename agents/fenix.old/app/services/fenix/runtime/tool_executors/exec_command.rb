require "securerandom"

module Fenix
  module Runtime
    module ToolExecutors
      module ExecCommand
        class << self
          def call(tool_call:, context:, collector:, control_client:, cancellation_probe:, current_execution_owner_id:, tool_invocation:, command_run:, **)
            normalized_tool_call = tool_call.deep_stringify_keys

            Fenix::Plugins::System::ExecCommand::Runtime.call(
              tool_call: normalized_tool_call,
              tool_invocation: normalize_tool_invocation(tool_invocation, normalized_tool_call),
              command_run: normalize_command_run(command_run, normalized_tool_call),
              workspace_root: context.dig("workspace_context", "workspace_root"),
              collector: collector,
              control_client: control_client,
              cancellation_probe: cancellation_probe,
              current_agent_task_run_id: current_execution_owner_id
            )
          end

          private

          def normalize_tool_invocation(tool_invocation, tool_call)
            tool_invocation&.deep_stringify_keys || {
              "tool_invocation_id" => "tool-invocation-#{tool_call.fetch("call_id", SecureRandom.uuid)}",
            }
          end

          def normalize_command_run(command_run, tool_call)
            return command_run&.deep_stringify_keys unless tool_call.fetch("tool_name") == "exec_command"

            command_run&.deep_stringify_keys || {
              "command_run_id" => "command-run-#{tool_call.fetch("call_id", SecureRandom.uuid)}",
            }
          end
        end
      end
    end
  end
end
