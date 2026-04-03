module Fenix
  module Runtime
    module ToolExecutors
      module Calculator
        class << self
          def call(tool_call:, **)
            expression = tool_call.dig("arguments", "expression").to_s
            left, operator, right = expression.strip.split(/\s+/, 3)
            left_value = Integer(left)
            right_value = Integer(right)

            case operator
            when "+"
              left_value + right_value
            when "-"
              left_value - right_value
            else
              raise ArgumentError, "unsupported calculator operator #{operator}"
            end
          end
        end
      end
    end
  end
end
