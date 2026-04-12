module EmbeddedAgents
  module ConversationSupervision
    class AppendMessage
      MAX_DEADLOCK_RETRIES = 2

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:, content:, supervision_access: nil)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
        @content = content
        @supervision_access = supervision_access
      end

      def call
        @conversation_supervision_session = @conversation_supervision_session.reload
        target_conversation = @conversation_supervision_session.target_conversation
        raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?
        target_conversation = target_conversation.reload
        supervision_access = resolved_supervision_access
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless supervision_access.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless supervision_access.append_message?
        raise EmbeddedAgents::Errors::ClosedSupervisionSession, "supervision session is closed" unless @conversation_supervision_session.open?

        control_decision = MaybeDispatchControlIntent.call(
          actor: @actor,
          conversation_supervision_session: @conversation_supervision_session,
          question: @content
        )
        snapshot = with_deadlock_retry do
          BuildSnapshot.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            supervision_access: supervision_access
          )
        end
        responder_output = respond(snapshot, control_decision:)
        user_message, supervisor_message = with_deadlock_retry do
          ApplicationRecord.transaction do
            [
              create_user_message(snapshot),
              create_supervisor_message(snapshot, responder_output),
            ]
          end
        end

        responder_output.merge(
          "user_message" => user_message,
          "supervisor_message" => supervisor_message
        )
      end

      private

      def with_deadlock_retry
        attempts = 0

        begin
          attempts += 1
          yield
        rescue ActiveRecord::Deadlocked
          raise if attempts > MAX_DEADLOCK_RETRIES

          sleep(0.01 * attempts)
          retry
        end
      end

      def resolved_supervision_access
        @supervision_access || AppSurface::Policies::ConversationSupervisionAccess.call(
          user: @actor,
          conversation_supervision_session: @conversation_supervision_session
        )
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
        when "summary_model"
          Responders::SummaryModel.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            conversation_supervision_snapshot: snapshot,
            question: @content,
            control_decision:
          )
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
