class AgentTaskRun < ApplicationRecord
  include HasPublicId
  include ClosableRuntimeResource
  include SupervisionStateFields

  enum :kind,
    {
      turn_step: "turn_step",
      agent_tool_call: "agent_tool_call",
      subagent_step: "subagent_step",
    },
    validate: true
  enum :lifecycle_state,
    {
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      interrupted: "interrupted",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :agent_program
  belongs_to :workflow_run
  belongs_to :workflow_node
  belongs_to :conversation
  belongs_to :turn
  belongs_to :subagent_session, optional: true
  belongs_to :origin_turn, class_name: "Turn", optional: true
  belongs_to :holder_agent_session, class_name: "AgentSession", optional: true

  has_many :agent_control_mailbox_items, dependent: :restrict_with_exception
  has_many :agent_control_report_receipts, dependent: :restrict_with_exception
  has_many :tool_bindings, dependent: :destroy
  has_many :tool_invocations, dependent: :destroy
  has_many :command_runs, dependent: :destroy
  has_one :execution_lease, as: :leased_resource, dependent: :restrict_with_exception

  validates :logical_work_id, presence: true
  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validate :task_payload_must_be_hash
  validate :progress_payload_must_be_hash
  validate :terminal_payload_must_be_hash
  validate :workflow_run_installation_match
  validate :agent_program_installation_match
  validate :workflow_node_installation_match
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :subagent_session_installation_match
  validate :origin_turn_installation_match
  validate :workflow_projection_match
  validate :agent_program_turn_match
  validate :holder_deployment_matches_task
  validate :lifecycle_timestamps

  after_create :freeze_tool_bindings!

  def holder_agent_program_version
    holder_agent_session&.agent_program_version
  end

  def feature_policy_snapshot
    turn&.feature_policy_snapshot || {}
  end

  private

  def task_payload_must_be_hash
    errors.add(:task_payload, "must be a hash") unless task_payload.is_a?(Hash)
  end

  def progress_payload_must_be_hash
    errors.add(:progress_payload, "must be a hash") unless progress_payload.is_a?(Hash)
  end

  def terminal_payload_must_be_hash
    errors.add(:terminal_payload, "must be a hash") unless terminal_payload.is_a?(Hash)
  end

  def workflow_run_installation_match
    return if workflow_run.blank? || workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def agent_program_installation_match
    return if agent_program.blank? || agent_program.installation_id == installation_id

    errors.add(:agent_program, "must belong to the same installation")
  end

  def workflow_node_installation_match
    return if workflow_node.blank? || workflow_node.installation_id == installation_id

    errors.add(:workflow_node, "must belong to the same installation")
  end

  def conversation_installation_match
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def turn_installation_match
    return if turn.blank? || turn.installation_id == installation_id

    errors.add(:turn, "must belong to the same installation")
  end

  def subagent_session_installation_match
    return if subagent_session.blank? || subagent_session.installation_id == installation_id

    errors.add(:subagent_session, "must belong to the same installation")
  end

  def origin_turn_installation_match
    return if origin_turn.blank? || origin_turn.installation_id == installation_id

    errors.add(:origin_turn, "must belong to the same installation")
  end

  def workflow_projection_match
    return if workflow_run.blank?

    errors.add(:workflow_node, "must belong to the same workflow run") if workflow_node.present? && workflow_node.workflow_run_id != workflow_run_id
    errors.add(:conversation, "must match the workflow run conversation") if conversation.present? && workflow_run.conversation_id != conversation_id
    errors.add(:turn, "must match the workflow run turn") if turn.present? && workflow_run.turn_id != turn_id
  end

  def agent_program_turn_match
    return if turn.blank? || agent_program.blank?
    return if turn.agent_program_version&.agent_program_id == agent_program_id

    errors.add(:agent_program, "must match the turn agent program")
  end

  def holder_deployment_matches_task
    return if holder_agent_session.blank?

    if holder_agent_session.installation_id != installation_id
      errors.add(:holder_agent_session, "must belong to the same installation")
    end

    if holder_agent_session.agent_program_id != agent_program_id
      errors.add(:holder_agent_session, "must belong to the task agent program")
    end
  end

  def lifecycle_timestamps
    if running?
      errors.add(:started_at, "must exist while the task is running") if started_at.blank?
      errors.add(:finished_at, "must be blank while the task is running") if finished_at.present?
      return
    end

    if queued?
      errors.add(:started_at, "must be blank while the task is queued") if started_at.present?
      errors.add(:finished_at, "must be blank while the task is queued") if finished_at.present?
      return
    end

    errors.add(:started_at, "must exist when the task has started") if started_at.blank?
    errors.add(:finished_at, "must exist when the task is terminal") if finished_at.blank?
  end

  def freeze_tool_bindings!
    ToolBindings::FreezeForTask.call(agent_task_run: self)
  end
end
