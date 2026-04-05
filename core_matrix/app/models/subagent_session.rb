class SubagentSession < ApplicationRecord
  include HasPublicId
  include ClosableRuntimeResource
  include SupervisionStateFields

  TERMINAL_OBSERVED_STATUSES = %w[completed failed interrupted].freeze
  DERIVED_CLOSE_STATUS_BY_CLOSE_STATE = {
    "open" => "open",
    "requested" => "close_requested",
    "acknowledged" => "close_requested",
    "closed" => "closed",
    "failed" => "closed",
  }.freeze

  enum :scope,
    {
      turn: "turn",
      conversation: "conversation",
    },
    prefix: :scope,
    validate: true
  enum :observed_status,
    {
      idle: "idle",
      running: "running",
      waiting: "waiting",
      completed: "completed",
      failed: "failed",
      interrupted: "interrupted",
    },
    prefix: :observed_status,
    validate: true

  belongs_to :installation
  belongs_to :conversation
  belongs_to :owner_conversation, class_name: "Conversation"
  belongs_to :origin_turn, class_name: "Turn", optional: true
  belongs_to :parent_subagent_session, class_name: "SubagentSession", optional: true

  has_many :child_subagent_sessions,
    class_name: "SubagentSession",
    foreign_key: :parent_subagent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :parent_subagent_session
  has_many :agent_task_runs, dependent: :restrict_with_exception
  has_many :delegated_agent_task_plan_items,
    class_name: "AgentTaskPlanItem",
    foreign_key: :delegated_subagent_session_id,
    dependent: :restrict_with_exception,
    inverse_of: :delegated_subagent_session
  has_many :agent_task_progress_entries, dependent: :restrict_with_exception
  has_one :execution_lease, as: :leased_resource, dependent: :restrict_with_exception

  scope :close_pending_or_open, -> { where(close_state: %w[open requested acknowledged]) }
  scope :running_for_barriers, -> { close_pending_or_open.where(observed_status: "running") }

  validates :profile_key, presence: true
  validates :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :conversation_installation_match
  validate :owner_conversation_installation_match
  validate :origin_turn_installation_match
  validate :parent_subagent_session_installation_match
  validate :scope_requires_origin_turn
  validate :depth_consistency

  def derived_close_status
    DERIVED_CLOSE_STATUS_BY_CLOSE_STATE.fetch(close_state) do
      raise ArgumentError, "unsupported subagent session close state #{close_state.inspect}"
    end
  end

  def close_pending?
    close_requested? || close_acknowledged?
  end

  def terminal_close?
    close_closed? || close_failed?
  end

  def close_pending_or_open?
    close_open? || close_pending?
  end

  def running_for_barriers?
    close_pending_or_open? && observed_status_running?
  end

  def terminal_for_wait?
    terminal_close? || TERMINAL_OBSERVED_STATUSES.include?(observed_status)
  end

  private

  def conversation_installation_match
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def owner_conversation_installation_match
    return if owner_conversation.blank? || owner_conversation.installation_id == installation_id

    errors.add(:owner_conversation, "must belong to the same installation")
  end

  def origin_turn_installation_match
    return if origin_turn.blank? || origin_turn.installation_id == installation_id

    errors.add(:origin_turn, "must belong to the same installation")
  end

  def parent_subagent_session_installation_match
    return if parent_subagent_session.blank? || parent_subagent_session.installation_id == installation_id

    errors.add(:parent_subagent_session, "must belong to the same installation")
  end

  def scope_requires_origin_turn
    return unless scope == "turn"
    return if origin_turn.present?

    errors.add(:origin_turn, "must exist for turn-scoped sessions")
  end

  def depth_consistency
    if parent_subagent_session.blank?
      errors.add(:depth, "must be zero when there is no parent session") unless depth.to_i.zero?
      return
    end

    return if depth == parent_subagent_session.depth + 1

    errors.add(:depth, "must be parent depth plus one")
  end
end
