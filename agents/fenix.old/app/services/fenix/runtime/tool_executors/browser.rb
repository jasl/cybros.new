module Fenix
  module Runtime
    module ToolExecutors
      module Browser
        class << self
          def call(tool_call:, current_execution_owner_id:, **)
            Fenix::Plugins::System::Browser::Runtime.call(
              tool_call: tool_call.deep_stringify_keys,
              current_agent_task_run_id: current_execution_owner_id
            )
          end
        end
      end
    end
  end
end
