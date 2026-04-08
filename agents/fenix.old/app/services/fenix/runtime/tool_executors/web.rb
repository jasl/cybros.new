module Fenix
  module Runtime
    module ToolExecutors
      module Web
        class << self
          def call(tool_call:, **)
            Fenix::Plugins::System::Web::Runtime.call(tool_call: tool_call.deep_stringify_keys)
          end
        end
      end
    end
  end
end
