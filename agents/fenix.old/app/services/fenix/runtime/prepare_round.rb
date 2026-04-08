require "json"

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
        prepared = Fenix::Hooks::PrepareTurn.call(context: round_context)
        compacted = Fenix::Hooks::CompactContext.call(
          messages: prepared.fetch("messages"),
          budget_hints: round_context.fetch("budget_hints"),
          likely_model: prepared.fetch("likely_model")
        )

        {
          "status" => "ok",
          "messages" => compacted.fetch("messages"),
          "visible_tool_names" => visible_tool_names,
          "likely_model" => prepared.fetch("likely_model"),
          "summary_artifacts" => [],
          "trace" => [prepared.fetch("trace"), compacted.fetch("trace")],
        }
      end

      private

      def round_context
        @round_context ||= Fenix::Runtime::PayloadContext.call(payload: @payload)
      end

      def visible_tool_names
        Array(round_context.dig("agent_context", "allowed_tool_names")).map(&:to_s)
      end
    end
  end
end
