class Message < ApplicationRecord
  TRANSCRIPT_BEARING_TYPES = %w[UserMessage AgentMessage].freeze

  enum :role, { user: "user", agent: "agent" }, validate: true
  enum :slot, { input: "input", output: "output" }, validate: true

  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn

  validates :content, presence: true
  validates :variant_index,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: [:turn_id, :slot] }
  validate :transcript_bearing_subclass_only
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :turn_conversation_match

  private

  def transcript_bearing_subclass_only
    return if TRANSCRIPT_BEARING_TYPES.include?(self.class.name)

    errors.add(:type, "must be a transcript-bearing subclass")
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def turn_installation_match
    return if turn.blank?
    return if turn.installation_id == installation_id

    errors.add(:turn, "must belong to the same installation")
  end

  def turn_conversation_match
    return if turn.blank? || conversation.blank?
    return if turn.conversation_id == conversation_id

    errors.add(:conversation, "must match the turn conversation")
  end
end
