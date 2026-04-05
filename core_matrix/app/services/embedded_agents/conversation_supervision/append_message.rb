module EmbeddedAgents
  module ConversationSupervision
    class AppendMessage
      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:, content:)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
        @content = content
      end

      def call
        @conversation_supervision_session = @conversation_supervision_session.reload
        target_conversation = @conversation_supervision_session.target_conversation
        raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?
        target_conversation = target_conversation.reload
        authority = Authority.call(
          actor: @actor,
          conversation_id: target_conversation.public_id
        )
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless authority.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless authority.allowed?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to append to supervision session" unless initiator_matches_actor?
        raise EmbeddedAgents::Errors::ClosedSupervisionSession, "supervision session is closed" unless @conversation_supervision_session.open?

        ApplicationRecord.transaction do
          control_decision = MaybeDispatchControlIntent.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            question: @content
          )
          snapshot = BuildSnapshot.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session
          )
          user_message = create_user_message(snapshot)
          responder_output = respond(snapshot, control_decision:)
          supervisor_message = create_supervisor_message(snapshot, responder_output)

          responder_output.merge(
            "user_message" => user_message,
            "supervisor_message" => supervisor_message
          )
        end
      end

      private

      def initiator_matches_actor?
        session_initiator = @conversation_supervision_session.initiator
        return false if session_initiator.blank? || @actor.blank?
        return false unless session_initiator.class == @actor.class

        session_initiator.id == @actor.id
      end

      def create_user_message(snapshot)
        @conversation_supervision_session.conversation_supervision_messages.create!(
          installation: @conversation_supervision_session.installation,
          target_conversation: @conversation_supervision_session.target_conversation,
          conversation_supervision_snapshot: snapshot,
          role: "user",
          content: @content
        )
      end

      def respond(snapshot, control_decision:)
        case @conversation_supervision_session.responder_strategy
        when "builtin"
          Responders::Builtin.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            conversation_supervision_snapshot: snapshot,
            question: @content,
            control_decision:
          )
        else
          raise ArgumentError, "unsupported conversation supervision responder strategy #{@conversation_supervision_session.responder_strategy.inspect}"
        end
      end

      def create_supervisor_message(snapshot, responder_output)
        @conversation_supervision_session.conversation_supervision_messages.create!(
          installation: @conversation_supervision_session.installation,
          target_conversation: @conversation_supervision_session.target_conversation,
          conversation_supervision_snapshot: snapshot,
          role: "supervisor_agent",
          content: responder_output.dig("human_sidechat", "content")
        )
      end
    end
  end
end
