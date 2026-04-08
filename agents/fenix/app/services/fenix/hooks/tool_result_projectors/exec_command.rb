module Fenix
  module Hooks
    module ToolResultProjectors
      module ExecCommand
        class << self
          def call(tool_name:, tool_result:)
            case tool_name
            when "exec_command"
              project_exec_command(tool_name: tool_name, tool_result: tool_result)
            when "command_run_list"
              {
                "tool_name" => tool_name,
                "content" => "Listed #{tool_result.fetch("entries").size} attached command runs.",
                "entries" => tool_result.fetch("entries"),
              }
            when "command_run_read_output"
              {
                "tool_name" => tool_name,
                "content" => "Read buffered output for command run #{tool_result.fetch("command_run_id")}.",
                "command_run_id" => tool_result.fetch("command_run_id"),
                "session_closed" => tool_result.fetch("session_closed"),
                "stdout_tail" => tool_result.fetch("stdout_tail"),
                "stderr_tail" => tool_result.fetch("stderr_tail"),
                "stdout_bytes" => tool_result.fetch("stdout_bytes"),
                "stderr_bytes" => tool_result.fetch("stderr_bytes"),
              }
            when "command_run_terminate"
              {
                "tool_name" => tool_name,
                "content" => "Terminated command run #{tool_result.fetch("command_run_id")}.",
                "command_run_id" => tool_result.fetch("command_run_id"),
                "terminated" => tool_result.fetch("terminated"),
                "session_closed" => tool_result.fetch("session_closed"),
                "exit_status" => tool_result["exit_status"],
                "stdout_bytes" => tool_result.fetch("stdout_bytes"),
                "stderr_bytes" => tool_result.fetch("stderr_bytes"),
                "stdout_tail" => tool_result.fetch("stdout_tail"),
                "stderr_tail" => tool_result.fetch("stderr_tail"),
              }.compact
            when "command_run_wait"
              {
                "tool_name" => tool_name,
                "content" => attached_session_content(
                  exit_status: tool_result.fetch("exit_status"),
                  output_streamed: tool_result.fetch("output_streamed")
                ),
                "command_run_id" => tool_result.fetch("command_run_id"),
                "session_closed" => tool_result.fetch("session_closed"),
                "exit_status" => tool_result.fetch("exit_status"),
                "output_streamed" => tool_result.fetch("output_streamed"),
                "stdout_bytes" => tool_result.fetch("stdout_bytes"),
                "stderr_bytes" => tool_result.fetch("stderr_bytes"),
                "stdout_tail" => tool_result.fetch("stdout_tail"),
                "stderr_tail" => tool_result.fetch("stderr_tail"),
              }
            when "write_stdin"
              if tool_result.fetch("session_closed", false)
                {
                  "tool_name" => tool_name,
                  "content" => attached_session_content(
                    exit_status: tool_result.fetch("exit_status"),
                    output_streamed: tool_result.fetch("output_streamed", false)
                  ),
                  "command_run_id" => tool_result.fetch("command_run_id"),
                  "session_closed" => true,
                  "exit_status" => tool_result.fetch("exit_status"),
                  "output_streamed" => tool_result.fetch("output_streamed", false),
                  "stdout_bytes" => tool_result.fetch("stdout_bytes", 0),
                  "stderr_bytes" => tool_result.fetch("stderr_bytes", 0),
                  "stdin_bytes" => tool_result.fetch("stdin_bytes", 0),
                }
              else
                {
                  "tool_name" => tool_name,
                  "content" => "Wrote #{tool_result.fetch("stdin_bytes", 0)} bytes to command run.",
                  "command_run_id" => tool_result.fetch("command_run_id"),
                  "session_closed" => false,
                  "stdin_bytes" => tool_result.fetch("stdin_bytes", 0),
                }
              end
            else
              raise ArgumentError, "unsupported exec command projection #{tool_name}"
            end
          end

          private

          def project_exec_command(tool_name:, tool_result:)
            stdout = tool_result.fetch("stdout", "")
            stderr = tool_result.fetch("stderr", "")
            output_streamed = tool_result.fetch("output_streamed", stdout.present? || stderr.present?)

            if tool_result["attached"] == true && !tool_result.fetch("session_closed", false)
              {
                "tool_name" => tool_name,
                "content" => "Command run started.",
                "command_run_id" => tool_result.fetch("command_run_id"),
                "attached" => true,
                "session_closed" => false,
              }
            else
              {
                "tool_name" => tool_name,
                "content" => command_content(exit_status: tool_result.fetch("exit_status"), output_streamed: output_streamed),
                "command_run_id" => tool_result["command_run_id"],
                "exit_status" => tool_result.fetch("exit_status"),
                "output_streamed" => output_streamed,
                "stdout_bytes" => tool_result.fetch("stdout_bytes", stdout.bytesize),
                "stderr_bytes" => tool_result.fetch("stderr_bytes", stderr.bytesize),
              }
            end
          end

          def command_content(exit_status:, output_streamed:)
            return "Command exited with status #{exit_status}." unless output_streamed

            "Command exited with status #{exit_status} after streaming output."
          end

          def attached_session_content(exit_status:, output_streamed:)
            return "Command run completed with status #{exit_status}." unless output_streamed

            "Command run completed with status #{exit_status} after streaming output."
          end
        end
      end
    end
  end
end
