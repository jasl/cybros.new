module Conversations
  module Metadata
    class BootstrapTitleJob < ApplicationJob
      TITLE_BOOTSTRAP_ORIGIN_KINDS = %w[manual_user channel_ingress].freeze

      queue_as :workflow_default

      def perform(conversation_id, turn_id)
        conversation = Conversation.find_by_public_id!(conversation_id)
        turn = Turn.find_by_public_id!(turn_id)
        return unless turn.conversation_id == conversation.id

        conversation.with_lock do
          message = selected_input_message_for(turn)
          return unless eligible_for_upgrade?(conversation, turn, message)

          title = Conversations::Metadata::GenerateBootstrapTitle.call(
            conversation: conversation,
            message: message,
            agent_definition_version: turn.agent_definition_version,
            actor: conversation.user
          )
          return if title.blank?
          return unless eligible_for_upgrade?(conversation, turn, message)

          conversation.update!(
            title: title,
            title_source: "bootstrap",
            title_updated_at: Time.current
          )
        end
      rescue ActiveRecord::RecordNotFound
        nil
      rescue StandardError => error
        Rails.logger.info("conversation title bootstrap skipped for #{conversation_id}/#{turn_id}: #{error.class}: #{error.message}")
        nil
      end

      private

      def selected_input_message_for(turn)
        turn.selected_input_message || turn.messages.find_by(role: "user", slot: "input")
      end

      def eligible_for_upgrade?(conversation, turn, message)
        return false if message.blank?
        return false unless message.user? && message.input?
        return false unless conversation.title_source_none?
        return false unless conversation.title_lock_state_unlocked?
        return false unless conversation.title == Conversations::Metadata::BootstrapTitle.placeholder_title
        return false unless TITLE_BOOTSTRAP_ORIGIN_KINDS.include?(turn.origin_kind)

        conversation.turns.where(origin_kind: TITLE_BOOTSTRAP_ORIGIN_KINDS).order(:sequence, :created_at, :id).limit(1).pick(:id) == turn.id
      end
    end
  end
end
