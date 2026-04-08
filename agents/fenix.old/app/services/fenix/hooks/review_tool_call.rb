module Fenix
  module Hooks
    class ReviewToolCall
      UnsupportedToolError = Class.new(StandardError)
      ToolNotVisibleError = Class.new(UnsupportedToolError)

      class << self
        def call(tool_call:, allowed_tool_names:)
          tool_call = tool_call.deep_stringify_keys
          tool_name = tool_call.fetch("tool_name")
          raise UnsupportedToolError, "unsupported tool #{tool_name}" unless supported_tool_names.include?(tool_name)
          unless Array(allowed_tool_names).map(&:to_s).include?(tool_name)
            raise ToolNotVisibleError, "tool #{tool_name} is not visible for this assignment"
          end

          tool_call
        end

        def supported_tool_names
          Fenix::Runtime::SystemToolRegistry.supported_tool_names
        end
      end
    end
  end
end
