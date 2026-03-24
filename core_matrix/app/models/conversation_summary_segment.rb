class ConversationSummarySegment < ApplicationRecord
  belongs_to :installation
  belongs_to :conversation
  belongs_to :start_message, class_name: "Message"
  belongs_to :end_message, class_name: "Message"
  belongs_to :superseded_by, class_name: "ConversationSummarySegment", optional: true

  has_many :conversation_imports,
    foreign_key: :summary_segment_id,
    dependent: :restrict_with_exception,
    inverse_of: :summary_segment
  has_many :superseded_segments,
    class_name: "ConversationSummarySegment",
    foreign_key: :superseded_by_id,
    dependent: :nullify,
    inverse_of: :superseded_by

  validates :content, presence: true
  validate :conversation_installation_match
  validate :start_message_installation_match
  validate :end_message_installation_match
  validate :messages_present_in_transcript_projection
  validate :transcript_range_order
  validate :superseded_by_rules

  private

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def start_message_installation_match
    return if start_message.blank?
    return if start_message.installation_id == installation_id

    errors.add(:start_message, "must belong to the same installation")
  end

  def end_message_installation_match
    return if end_message.blank?
    return if end_message.installation_id == installation_id

    errors.add(:end_message, "must belong to the same installation")
  end

  def messages_present_in_transcript_projection
    return if conversation.blank? || start_message.blank? || end_message.blank?

    projection_message_ids = conversation.transcript_projection_messages.map(&:id)

    errors.add(:start_message, "must be present in the conversation transcript projection") unless projection_message_ids.include?(start_message_id)
    errors.add(:end_message, "must be present in the conversation transcript projection") unless projection_message_ids.include?(end_message_id)
  end

  def transcript_range_order
    return if conversation.blank? || start_message.blank? || end_message.blank?

    projection_message_ids = conversation.transcript_projection_messages.map(&:id)
    start_index = projection_message_ids.index(start_message_id)
    end_index = projection_message_ids.index(end_message_id)
    return if start_index.blank? || end_index.blank?
    return if start_index <= end_index

    errors.add(:end_message, "must come after the start message in transcript order")
  end

  def superseded_by_rules
    return if superseded_by.blank?

    errors.add(:superseded_by, "must belong to the same installation") unless superseded_by.installation_id == installation_id
    errors.add(:superseded_by, "must belong to the same conversation") unless superseded_by.conversation_id == conversation_id
    errors.add(:superseded_by, "must not be the same segment") if superseded_by_id == id
  end
end
