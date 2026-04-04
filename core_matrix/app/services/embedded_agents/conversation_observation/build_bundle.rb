module EmbeddedAgents
  module ConversationObservation
    class BuildBundle
      def self.call(...)
        new(...).call
      end

      def initialize(conversation_observation_frame:)
        @conversation_observation_frame = conversation_observation_frame
      end

      def call
        snapshot = @conversation_observation_frame.bundle_snapshot
        raise ArgumentError, "observation frame is missing a frozen bundle snapshot" unless snapshot.is_a?(Hash) && snapshot.present?

        snapshot.deep_dup
      end
    end
  end
end
