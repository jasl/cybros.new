class ConversationMessageVisibility < ApplicationRecord
  belongs_to :installation
  belongs_to :conversation
  belongs_to :message

  validates :message_id, uniqueness: { scope: :conversation_id }
  validate :overlay_state_present
  validate :conversation_installation_match
  validate :message_installation_match

  private

  def overlay_state_present
    return if hidden? || excluded_from_context?

    errors.add(:base, "must hide the message or exclude it from context")
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def message_installation_match
    return if message.blank?
    return if message.installation_id == installation_id

    errors.add(:message, "must belong to the same installation")
  end
end
