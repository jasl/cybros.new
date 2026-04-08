module Fenix
  module Runtime
    module ToolExecutors
      module Workspace
        class << self
          def call(tool_call:, context:, **)
            Fenix::Plugins::System::Workspace::Runtime.call(
              tool_call: tool_call.deep_stringify_keys,
              workspace_root: context.dig("workspace_context", "workspace_root")
            )
          end
        end
      end
    end
  end
end
