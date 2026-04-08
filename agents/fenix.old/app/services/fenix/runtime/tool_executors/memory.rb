module Fenix
  module Runtime
    module ToolExecutors
      module Memory
        class << self
          def call(tool_call:, context:, **)
            Fenix::Plugins::System::Memory::Runtime.call(
              tool_call: tool_call.deep_stringify_keys,
              workspace_root: context.dig("workspace_context", "workspace_root"),
              conversation_id: context.fetch("conversation_id"),
              agent_program_version_id: context.dig("runtime_identity", "agent_program_version_id")
            )
          end
        end
      end
    end
  end
end
