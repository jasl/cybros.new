class ConversationCloseOperation < ApplicationRecord
  include HasPublicId

  TERMINAL_STATES = %w[completed degraded].freeze

  enum :intent_kind,
    {
      archive: "archive",
      delete: "delete",
    },
    prefix: :intent,
    validate: true
  enum :lifecycle_state,
    {
      requested: "requested",
      quiescing: "quiescing",
      disposing: "disposing",
      completed: "completed",
      degraded: "degraded",
    },
    prefix: :lifecycle,
    validate: true

  belongs_to :installation
  belongs_to :conversation

  validate :summary_payload_must_be_hash
  validate :conversation_installation_match
  validate :completed_at_consistency
  validate :unfinished_operation_uniqueness

  private

  def summary_payload_must_be_hash
    errors.add(:summary_payload, "must be a hash") unless summary_payload.is_a?(Hash)
  end

  def conversation_installation_match
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def completed_at_consistency
    if TERMINAL_STATES.include?(lifecycle_state)
      errors.add(:completed_at, "must exist when close operation is terminal") if completed_at.blank?
      return
    end

    errors.add(:completed_at, "must be blank while close operation is unfinished") if completed_at.present?
  end

  def unfinished_operation_uniqueness
    return if lifecycle_state.blank? || TERMINAL_STATES.include?(lifecycle_state)

    existing_operation = self.class
      .where(conversation_id: conversation_id)
      .where.not(lifecycle_state: TERMINAL_STATES)
      .where.not(id: id)
      .exists?
    return unless existing_operation

    errors.add(:conversation, "already has an unfinished close operation")
  end
end
