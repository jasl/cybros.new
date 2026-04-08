module Fenix
  module Hooks
    class ProjectToolResult
      def self.call(tool_call:, tool_result:)
        tool_name = tool_call.fetch("tool_name")
        Fenix::Runtime::SystemToolRegistry.fetch!(tool_name)
          .fetch(:projector)
          .call(tool_name: tool_name, tool_result: tool_result)
      end
    end
  end
end
