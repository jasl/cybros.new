class ConversationClosure < ApplicationRecord
  belongs_to :installation
  belongs_to :ancestor_conversation,
    class_name: "Conversation",
    inverse_of: :descendant_closures
  belongs_to :descendant_conversation,
    class_name: "Conversation",
    inverse_of: :ancestor_closures

  validates :ancestor_conversation_id,
    uniqueness: { scope: [:installation_id, :descendant_conversation_id] }
  validates :depth,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ancestor_installation_match
  validate :descendant_installation_match

  private

  def ancestor_installation_match
    return if ancestor_conversation.blank?
    return if ancestor_conversation.installation_id == installation_id

    errors.add(:ancestor_conversation, "must belong to the same installation")
  end

  def descendant_installation_match
    return if descendant_conversation.blank?
    return if descendant_conversation.installation_id == installation_id

    errors.add(:descendant_conversation, "must belong to the same installation")
  end
end
