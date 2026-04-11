module Runtime
  module Assignments
    class DispatchMode
      def self.call(...)
        new(...).call
      end

      def initialize(task_payload:, runtime_context:)
        @task_payload = task_payload.deep_stringify_keys
        @runtime_context = runtime_context.deep_stringify_keys
      end

      def call
        case @task_payload["mode"]
        when "raise_error"
          { "kind" => "raise_error" }
        when /\Askills_/
          {
            "kind" => "unsupported_skill_flow",
            "mode" => @task_payload["mode"],
          }
        else
          { "kind" => "deterministic_tool" }
        end
      end
    end
  end
end
