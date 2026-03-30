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

          {
            "tool_name" => tool_name,
            "content" => stdout.presence || stderr.presence || "Command exited with status #{exit_status}.",
            "exit_status" => exit_status,
            "stdout" => stdout,
            "stderr" => stderr,
          }
        else
          raise ArgumentError, "unsupported tool projection #{tool_name}"
        end
      end
    end
  end
end
