module Fenix
  module Hooks
    class ProjectToolResult
      def self.call(tool_call:, tool_result:)
        {
          "tool_name" => tool_call.fetch("tool_name"),
          "content" => "The calculator returned #{tool_result}.",
        }
      end
    end
  end
end
