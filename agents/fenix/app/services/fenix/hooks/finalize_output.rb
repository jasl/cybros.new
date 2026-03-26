module Fenix
  module Hooks
    class FinalizeOutput
      def self.call(projected_result:, context:)
        {
          "output" => projected_result.fetch("content"),
          "conversation_id" => context.fetch("conversation_id"),
          "turn_id" => context.fetch("turn_id"),
        }
      end
    end
  end
end
