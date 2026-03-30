module Fenix
  module Hooks
    class ReviewToolCall
      UnsupportedToolError = Class.new(StandardError)
      ToolNotVisibleError = Class.new(UnsupportedToolError)

      SUPPORTED_TOOLS = {
        "calculator" => true,
        "exec_command" => true,
        "write_stdin" => true,
        "shell_exec" => true,
      }.freeze

      def self.call(tool_call:, allowed_tool_names:)
        tool_call = tool_call.deep_stringify_keys
        tool_name = tool_call.fetch("tool_name")
        raise UnsupportedToolError, "unsupported tool #{tool_name}" unless SUPPORTED_TOOLS.key?(tool_name)
        unless Array(allowed_tool_names).map(&:to_s).include?(tool_name)
          raise ToolNotVisibleError, "tool #{tool_name} is not visible for this assignment"
        end

        tool_call
      end
    end
  end
end
