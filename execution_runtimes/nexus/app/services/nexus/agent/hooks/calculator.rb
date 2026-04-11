module Nexus
  module Agent
    module Hooks
      class Calculator
        InvalidExpressionError = Class.new(StandardError)

        def self.call(...)
          new(...).call
        end

        def initialize(expression:)
          @expression = expression.to_s
        end

        def call
          match = @expression.match(/\A\s*(-?\d+)\s*(\S+)\s*(-?\d+)\s*\z/)
          raise InvalidExpressionError, "invalid arithmetic expression #{@expression.inspect}" unless match

          left = Integer(match[1], 10)
          operator = match[2]
          right = Integer(match[3], 10)

          case operator
          when "+"
            left + right
          when "-"
            left - right
          when "*"
            left * right
          when "/"
            raise InvalidExpressionError, "division by zero is not supported" if right.zero?

            quotient = left.fdiv(right)
            quotient == quotient.to_i ? quotient.to_i : quotient
          else
            raise InvalidExpressionError, "unsupported arithmetic operator #{operator}"
          end
        end
      end
    end
  end
end
