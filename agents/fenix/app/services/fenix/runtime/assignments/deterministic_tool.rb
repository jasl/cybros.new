module Fenix
  module Runtime
    module Assignments
      class DeterministicTool
        InvalidRequestError = Class.new(StandardError)

        def self.call(...)
          new(...).call
        end

        def initialize(task_payload:)
          @task_payload = task_payload.deep_stringify_keys
        end

        def call
          return arithmetic_output if expression.present?
          return echo_output if echo_text.present?

          raise InvalidRequestError, "deterministic tool request requires expression or echo_text"
        end

        private

        def arithmetic_output
          match = expression.match(/\A\s*(-?\d+)\s*(\S+)\s*(-?\d+)\s*\z/)
          raise InvalidRequestError, "invalid arithmetic expression #{expression.inspect}" unless match

          left = Integer(match[1], 10)
          operator = match[2]
          right = Integer(match[3], 10)

          result = case operator
          when "+"
            left + right
          when "-"
            left - right
          when "*"
            left * right
          when "/"
            raise InvalidRequestError, "division by zero is not supported" if right.zero?

            quotient = left.fdiv(right)
            quotient == quotient.to_i ? quotient.to_i : quotient
          else
            raise InvalidRequestError, "unsupported arithmetic operator #{operator}"
          end

          {
            "kind" => "calculator",
            "expression" => expression,
            "result" => result,
            "content" => "The calculator returned #{result}.",
          }
        end

        def echo_output
          {
            "kind" => "echo",
            "text" => echo_text,
            "content" => "Echo: #{echo_text}",
          }
        end

        def expression
          @expression ||= @task_payload["expression"].to_s.presence
        end

        def echo_text
          @echo_text ||= @task_payload["echo_text"].to_s.presence || @task_payload["text"].to_s.presence
        end
      end
    end
  end
end
