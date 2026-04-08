require "securerandom"

module Fenix
  module Runtime
    module ToolExecutors
      module Process
        class << self
          def call(tool_call:, control_client:, current_execution_owner_id:, process_run:, **)
            normalized_tool_call = tool_call.deep_stringify_keys

            Fenix::Plugins::System::Process::Runtime.call(
              tool_call: normalized_tool_call,
              process_run: normalize_process_run(process_run, normalized_tool_call, current_execution_owner_id),
              control_client: control_client,
              current_agent_task_run_id: current_execution_owner_id
            )
          end

          private

          def normalize_process_run(process_run, tool_call, current_execution_owner_id)
            return process_run&.deep_stringify_keys unless tool_call.fetch("tool_name") == "process_exec"

            process_run&.deep_stringify_keys || {
              "process_run_id" => "process-run-#{tool_call.fetch("call_id", SecureRandom.uuid)}",
              "agent_task_run_id" => current_execution_owner_id,
            }
          end
        end
      end
    end
  end
end
