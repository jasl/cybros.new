module EmbeddedAgents
  module ConversationObservation
    class AppendMessage
      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_observation_session:, content:)
        @actor = actor
        @conversation_observation_session = conversation_observation_session
        @content = content
      end

      def call
        @conversation_observation_session = @conversation_observation_session.reload
        target_conversation = @conversation_observation_session.target_conversation.reload
        authority = Authority.call(
          actor: @actor,
          conversation_id: target_conversation.public_id
        )
        raise EmbeddedAgents::Errors::UnauthorizedObservation, "not allowed to observe conversation" unless authority.allowed?
        raise EmbeddedAgents::Errors::UnauthorizedObservation, "not allowed to append to observation session" unless initiator_matches_actor?
        raise EmbeddedAgents::Errors::ClosedObservationSession, "observation session is closed" unless @conversation_observation_session.open?

        ApplicationRecord.transaction do
          frame = BuildFrame.call(conversation_observation_session: @conversation_observation_session)
          user_message = create_user_message(frame)
          observation_bundle = BuildBundle.call(conversation_observation_frame: frame)
          responder_output = RouteResponder.call(
            conversation_observation_session: @conversation_observation_session,
            conversation_observation_frame: frame,
            observation_bundle: observation_bundle,
            question: @content
          )
          observer_message = create_observer_message(frame, responder_output)

          responder_output.merge(
            "user_message" => user_message,
            "observer_message" => observer_message
          )
        end
      end

      private

      def initiator_matches_actor?
        session_initiator = @conversation_observation_session.initiator
        return false if session_initiator.blank? || @actor.blank?
        return false unless session_initiator.class == @actor.class

        session_initiator.id == @actor.id
      end

      def create_user_message(frame)
        @conversation_observation_session.conversation_observation_messages.create!(
          installation: @conversation_observation_session.installation,
          target_conversation: @conversation_observation_session.target_conversation,
          conversation_observation_frame: frame,
          role: "user",
          content: @content
        )
      end

      def create_observer_message(frame, responder_output)
        human_sidechat = responder_output.fetch("human_sidechat")
        supervisor_status = responder_output.fetch("supervisor_status")

        @conversation_observation_session.conversation_observation_messages.create!(
          installation: @conversation_observation_session.installation,
          target_conversation: @conversation_observation_session.target_conversation,
          conversation_observation_frame: frame,
          role: "observer_agent",
          content: human_sidechat.fetch("content")
        )
      end
    end
  end
end
