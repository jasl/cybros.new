module Nexus
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
          result = Nexus::Agent::Hooks::Calculator.call(expression: expression)

          {
            "kind" => "calculator",
            "expression" => expression,
            "result" => result,
            "content" => "The calculator returned #{result}.",
          }
        rescue Nexus::Agent::Hooks::Calculator::InvalidExpressionError => error
          raise InvalidRequestError, error.message
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
