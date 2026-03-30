module Fenix
  module Hooks
    class ProjectToolResult
      def self.call(tool_call:, tool_result:)
        tool_name = tool_call.fetch("tool_name")

        case tool_name
        when "calculator"
          {
            "tool_name" => tool_name,
            "content" => "The calculator returned #{tool_result}.",
          }
        when "exec_command"
          project_exec_command(tool_name:, tool_result:)
        when "process_exec"
          project_process_exec(tool_name:, tool_result:)
        when "write_stdin"
          project_write_stdin(tool_name:, tool_result:)
        else
          raise ArgumentError, "unsupported tool projection #{tool_name}"
        end
      end

      def self.project_exec_command(tool_name:, tool_result:)
        stdout = tool_result.fetch("stdout", "")
        stderr = tool_result.fetch("stderr", "")
        output_streamed = tool_result.fetch("output_streamed", stdout.present? || stderr.present?)

        if tool_result["attached"] == true && !tool_result.fetch("session_closed", false)
          {
            "tool_name" => tool_name,
            "content" => "Command session started.",
            "command_run_id" => tool_result.fetch("command_run_id"),
            "attached" => true,
            "session_closed" => false,
          }
        else
          {
            "tool_name" => tool_name,
            "content" => command_content(exit_status: tool_result.fetch("exit_status"), output_streamed:),
            "command_run_id" => tool_result["command_run_id"],
            "exit_status" => tool_result.fetch("exit_status"),
            "output_streamed" => output_streamed,
            "stdout_bytes" => tool_result.fetch("stdout_bytes", stdout.bytesize),
            "stderr_bytes" => tool_result.fetch("stderr_bytes", stderr.bytesize),
          }
        end
      end

      def self.project_write_stdin(tool_name:, tool_result:)
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
            "content" => "Wrote #{tool_result.fetch("stdin_bytes", 0)} bytes to command session.",
            "command_run_id" => tool_result.fetch("command_run_id"),
            "session_closed" => false,
            "stdin_bytes" => tool_result.fetch("stdin_bytes", 0),
          }
        end
      end

      def self.project_process_exec(tool_name:, tool_result:)
        {
          "tool_name" => tool_name,
          "content" => "Background service started as process run #{tool_result.fetch("process_run_id")}.",
          "process_run_id" => tool_result.fetch("process_run_id"),
          "lifecycle_state" => tool_result.fetch("lifecycle_state"),
        }
      end

      def self.command_content(exit_status:, output_streamed:)
        return "Command exited with status #{exit_status}." unless output_streamed

        "Command exited with status #{exit_status} after streaming output."
      end

      def self.attached_session_content(exit_status:, output_streamed:)
        return "Command session completed with status #{exit_status}." unless output_streamed

        "Command session completed with status #{exit_status} after streaming output."
      end
    end
  end
end
