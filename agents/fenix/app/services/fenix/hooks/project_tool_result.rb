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
        when "shell_exec"
          stdout = tool_result.fetch("stdout", "")
          stderr = tool_result.fetch("stderr", "")
          exit_status = tool_result.fetch("exit_status")
          output_streamed = stdout.present? || stderr.present?

          {
            "tool_name" => tool_name,
            "content" => shell_exec_content(exit_status:, output_streamed:),
            "exit_status" => exit_status,
            "output_streamed" => output_streamed,
            "stdout_bytes" => stdout.bytesize,
            "stderr_bytes" => stderr.bytesize,
          }
        else
          raise ArgumentError, "unsupported tool projection #{tool_name}"
        end
      end

      def self.shell_exec_content(exit_status:, output_streamed:)
        return "Command exited with status #{exit_status}." unless output_streamed

        "Command exited with status #{exit_status} after streaming output."
      end
    end
  end
end
