class ConversationEvent < ApplicationRecord
  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn, optional: true
  belongs_to :source, polymorphic: true, optional: true

  validates :event_kind, presence: true
  validates :projection_sequence,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :conversation_id }
  validate :payload_must_be_hash
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :turn_conversation_match
  validate :stream_pairing
  validate :source_installation_match
  validate :source_conversation_match

  def self.live_projection(conversation:)
    projection = []
    stream_positions = {}

    where(conversation: conversation).order(:projection_sequence).each do |event|
      if event.stream_key.present?
        if stream_positions.key?(event.stream_key)
          projection[stream_positions[event.stream_key]] = event
        else
          stream_positions[event.stream_key] = projection.length
          projection << event
        end
      else
        projection << event
      end
    end

    projection
  end

  private

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
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

    errors.add(:turn, "must belong to the same conversation")
  end

  def stream_pairing
    if stream_key.present?
      errors.add(:stream_revision, "must exist when stream_key is present") if stream_revision.blank?
      return
    end

    errors.add(:stream_revision, "must be blank when stream_key is blank") if stream_revision.present?
  end

  def source_installation_match
    return if source.blank?
    return unless source.respond_to?(:installation_id)
    return if source.installation_id == installation_id

    errors.add(:source, "must belong to the same installation")
  end

  def source_conversation_match
    return if source.blank?
    return unless source.respond_to?(:conversation_id)
    return if source.conversation_id == conversation_id

    errors.add(:source, "must belong to the same conversation")
  end
end
