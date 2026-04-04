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
        authority = Authority.call(
          actor: @actor,
          conversation_id: @conversation_observation_session.target_conversation.public_id
        )
        raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless authority.allowed?

        frame = BuildFrame.call(conversation_observation_session: @conversation_observation_session)
        user_message = create_user_message(frame)
        observation_bundle = BuildBundle.call(conversation_observation_frame: frame)
        responder_output = RouteResponder.call(
          conversation_observation_session: @conversation_observation_session,
          conversation_observation_frame: frame,
          observation_bundle: observation_bundle
        )
        observer_message = create_observer_message(frame, responder_output)

        responder_output.merge(
          "user_message" => user_message,
          "observer_message" => observer_message
        )
      end

      private

      def create_user_message(frame)
        @conversation_observation_session.conversation_observation_messages.create!(
          installation: @conversation_observation_session.installation,
          target_conversation: @conversation_observation_session.target_conversation,
          conversation_observation_frame: frame,
          role: "user",
          content: @content,
          metadata: {}
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
          content: human_sidechat.fetch("content"),
          metadata: {
            "proof_refs" => human_sidechat.fetch("proof_refs"),
            "supervisor_status" => supervisor_status,
          }
        )
      end
    end
  end
end
