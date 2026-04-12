module AppSurface
  module Policies
    class ConversationSupervisionAccess
      CONTROL_VERBS = %w[
        request_status_refresh
        request_turn_interrupt
        request_conversation_close
        send_guidance_to_active_agent
        send_guidance_to_subagent
        request_subagent_close
        retry_blocked_step
        resume_waiting_workflow
      ].freeze

      attr_reader :conversation_supervision_session, :policy

      def self.call(...)
        new(...)
      end

      def initialize(user:, conversation: nil, conversation_supervision_session: nil)
        @user = user
        @conversation = conversation
        @conversation_supervision_session = conversation_supervision_session
        @policy = resolved_conversation&.conversation_capability_policy
      end

      def read?
        resolved_conversation.present? &&
          AppSurface::Policies::ConversationAccess.call(
            user: @user,
            conversation: resolved_conversation
          )
      end

      def create_session?
        read? && side_chat_enabled?
      end

      def append_message?
        read? && side_chat_enabled? && initiator_matches_user?
      end

      def close_session?
        read? && side_chat_enabled?
      end

      def supervision_enabled?
        policy&.supervision_enabled? == true
      end

      def detailed_progress_enabled?
        supervision_enabled? && policy&.detailed_progress_enabled? == true
      end

      def side_chat_enabled?
        supervision_enabled? && policy&.side_chat_enabled? == true
      end

      def control_enabled?
        side_chat_enabled? && policy&.control_enabled? == true
      end

      def available_control_verbs
        control_enabled? ? CONTROL_VERBS : []
      end

      private

      def resolved_conversation
        @resolved_conversation ||= @conversation || conversation_supervision_session&.target_conversation
      end

      def initiator_matches_user?
        return false if conversation_supervision_session.blank?

        initiator = conversation_supervision_session.initiator
        return false if initiator.blank? || @user.blank?
        return false unless initiator.class == @user.class

        initiator.id == @user.id
      end
    end
  end
end
