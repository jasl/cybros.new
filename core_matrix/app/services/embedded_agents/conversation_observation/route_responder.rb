module EmbeddedAgents
  module ConversationObservation
    class RouteResponder
      def self.call(...)
        new(...).call
      end

      def initialize(conversation_observation_session:, conversation_observation_frame:, observation_bundle:)
        @conversation_observation_session = conversation_observation_session
        @conversation_observation_frame = conversation_observation_frame
        @observation_bundle = observation_bundle
      end

      def call
        case @conversation_observation_session.responder_strategy
        when "builtin"
          Responders::Builtin.call(
            conversation_observation_frame: @conversation_observation_frame,
            observation_bundle: @observation_bundle
          )
        else
          raise ArgumentError, "unsupported conversation observation responder strategy #{@conversation_observation_session.responder_strategy.inspect}"
        end
      end
    end
  end
end
