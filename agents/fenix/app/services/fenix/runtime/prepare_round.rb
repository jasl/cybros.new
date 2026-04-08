module Fenix
  module Runtime
    class PrepareRound
      def self.call(...)
        new(...).call
      end

      def initialize(payload:)
        @payload = payload.deep_stringify_keys
      end

      def call
        instructions = Fenix::Application::BuildRoundInstructions.call(context: round_context)

        {
          "status" => "ok",
          "messages" => instructions.fetch("messages"),
          "visible_tool_names" => instructions.fetch("visible_tool_names"),
          "summary_artifacts" => [],
          "trace" => [],
        }
      end

      private

      def round_context
        @round_context ||= Fenix::Runtime::PayloadContext.call(payload: @payload)
      end
    end
  end
end
