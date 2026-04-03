module Fenix
  module Hooks
    module ToolResultProjectors
      module Calculator
        class << self
          def call(tool_name:, tool_result:)
            {
              "tool_name" => tool_name,
              "content" => "The calculator returned #{tool_result}.",
            }
          end
        end
      end
    end
  end
end
