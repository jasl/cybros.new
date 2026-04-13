class ConversationSupervisionFeedEntry < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  EVENT_KINDS = %w[
    turn_started
    turn_todo_item_started
    turn_todo_item_completed
    turn_todo_item_blocked
    turn_todo_item_canceled
    turn_todo_item_failed
    waiting_started
    waiting_cleared
    blocker_started
    blocker_cleared
    control_requested
    control_completed
    control_failed
    turn_completed
    turn_failed
    turn_interrupted
  ].freeze

  data_lifecycle_kind! :recomputable

  belongs_to :installation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :target_turn, class_name: "Turn", optional: true

  validates :event_kind, :summary, :occurred_at, presence: true
  validates :event_kind, inclusion: { in: EVENT_KINDS }
  validates :sequence,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :target_conversation_id }
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :details_payload_must_be_hash
  validate :installation_alignment
  validate :target_conversation_owner_context_match
  validate :summary_must_not_expose_internal_tokens

  private

  def details_payload_must_be_hash
    errors.add(:details_payload, "must be a hash") unless details_payload.is_a?(Hash)
  end

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
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

  def target_conversation_owner_context_match
    return if target_conversation.blank?

    errors.add(:user, "must match the target conversation user") if user.present? && target_conversation.user_id != user_id
    errors.add(:workspace, "must match the target conversation workspace") if workspace.present? && target_conversation.workspace_id != workspace_id
    errors.add(:agent, "must match the target conversation agent") if agent.present? && target_conversation.agent_id != agent_id
  end

  def summary_must_not_expose_internal_tokens
    return unless summary.present?
    return unless AgentTaskProgressEntry::INTERNAL_RUNTIME_TOKEN_PATTERN.match?(summary)

    errors.add(:summary, "must not expose internal runtime tokens")
  end
end
