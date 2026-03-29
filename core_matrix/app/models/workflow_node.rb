class WorkflowNode < ApplicationRecord
  include HasPublicId

  attribute :lifecycle_state, :string

  enum :decision_source,
    {
      llm: "llm",
      agent_program: "agent_program",
      system: "system",
      user: "user",
    },
    validate: true
  enum :lifecycle_state,
    {
      pending: "pending",
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true
  enum :presentation_policy,
    {
      internal_only: "internal_only",
      ops_trackable: "ops_trackable",
      user_projectable: "user_projectable",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workspace
  belongs_to :conversation
  belongs_to :turn
  belongs_to :yielding_workflow_node, class_name: "WorkflowNode", optional: true

  has_many :outgoing_edges,
    class_name: "WorkflowEdge",
    foreign_key: :from_node_id,
    dependent: :restrict_with_exception,
    inverse_of: :from_node
  has_many :incoming_edges,
    class_name: "WorkflowEdge",
    foreign_key: :to_node_id,
    dependent: :restrict_with_exception,
    inverse_of: :to_node
  has_many :workflow_artifacts, dependent: :restrict_with_exception
  has_many :workflow_node_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :process_runs, dependent: :restrict_with_exception
  has_many :execution_leases, dependent: :restrict_with_exception
  has_many :yielded_workflow_nodes,
    class_name: "WorkflowNode",
    foreign_key: :yielding_workflow_node_id,
    dependent: :nullify,
    inverse_of: :yielding_workflow_node

  before_validation :default_projection_fields_from_workflow_run

  validates :node_key, presence: true, uniqueness: { scope: :workflow_run_id }
  validates :node_type, presence: true
  validates :ordinal,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :workflow_run_id }
  validates :stage_index,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :stage_position,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validate :workflow_run_installation_match
  validate :workspace_installation_match
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :workflow_projection_match
  validate :yielding_workflow_integrity
  validate :execution_timestamps_consistency
  validate :metadata_must_be_hash

  def terminal?
    completed? || failed? || canceled?
  end

  private

  def default_projection_fields_from_workflow_run
    return if workflow_run.blank?

    self.workspace ||= workflow_run.workspace
    self.conversation ||= workflow_run.conversation
    self.turn ||= workflow_run.turn
  end

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
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

  def workflow_projection_match
    return if workflow_run.blank?

    if workspace.present? && workflow_run.workspace_id != workspace_id
      errors.add(:workspace, "must match the workflow run workspace")
    end
    if conversation.present? && workflow_run.conversation_id != conversation_id
      errors.add(:conversation, "must match the workflow run conversation")
    end
    if turn.present? && workflow_run.turn_id != turn_id
      errors.add(:turn, "must match the workflow run turn")
    end
  end

  def yielding_workflow_integrity
    return if yielding_workflow_node.blank?
    return if yielding_workflow_node.workflow_run_id == workflow_run_id

    errors.add(:yielding_workflow_node, "must belong to the same workflow run")
  end

  def execution_timestamps_consistency
    if pending? || queued?
      errors.add(:started_at, "must be blank before execution starts") if started_at.present?
      errors.add(:finished_at, "must be blank before execution finishes") if finished_at.present?
    end

    if running?
      errors.add(:started_at, "must exist while execution is running") if started_at.blank?
      errors.add(:finished_at, "must be blank while execution is running") if finished_at.present?
    end

    if terminal?
      errors.add(:finished_at, "must exist when execution has finished") if finished_at.blank?
    end

    if completed? || failed?
      errors.add(:started_at, "must exist when execution has finished") if started_at.blank?
    end

    return if started_at.blank? || finished_at.blank?
    return unless finished_at < started_at

    errors.add(:finished_at, "must be after started_at")
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end
end
