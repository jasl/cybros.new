class ConversationSupervisionFeedEntry < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  EVENT_KINDS = %w[
    turn_started
    progress_recorded
    waiting_started
    waiting_cleared
    blocker_started
    blocker_cleared
    subagent_started
    subagent_completed
    control_requested
    control_completed
    control_failed
    turn_completed
    turn_failed
    turn_interrupted
  ].freeze

  data_lifecycle_kind! :recomputable

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :target_turn, class_name: "Turn", optional: true

  validates :event_kind, :summary, :occurred_at, presence: true
  validates :event_kind, inclusion: { in: EVENT_KINDS }
  validates :sequence,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :target_conversation_id }
  validate :details_payload_must_be_hash
  validate :installation_alignment
  validate :summary_must_not_expose_internal_tokens

  private

  def details_payload_must_be_hash
    errors.add(:details_payload, "must be a hash") unless details_payload.is_a?(Hash)
  end

  def installation_alignment
    if target_conversation.present? && target_conversation.installation_id != installation_id
      errors.add(:target_conversation, "must belong to the same installation")
    end

    if target_turn.present? && target_turn.installation_id != installation_id
      errors.add(:target_turn, "must belong to the same installation")
    end

    if target_turn.present? &&
        target_conversation.present? &&
        target_turn.conversation_id != target_conversation_id
      errors.add(:target_turn, "must belong to the target conversation")
    end
  end

  def summary_must_not_expose_internal_tokens
    return unless summary.present?
    return unless AgentTaskProgressEntry::INTERNAL_RUNTIME_TOKEN_PATTERN.match?(summary)

    errors.add(:summary, "must not expose internal runtime tokens")
  end
end
