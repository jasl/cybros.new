module Fenix
  module Hooks
    class ReviewToolCall
      UnsupportedToolError = Class.new(StandardError)

      SUPPORTED_TOOLS = {
        "calculator" => true,
      }.freeze

      def self.call(tool_call:)
        tool_call = tool_call.deep_stringify_keys
        tool_name = tool_call.fetch("tool_name")
        raise UnsupportedToolError, "unsupported tool #{tool_name}" unless SUPPORTED_TOOLS.key?(tool_name)

        tool_call
      end
    end
  end
end
