class SubagentRun < ApplicationRecord
  enum :lifecycle_state,
    {
      running: "running",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workflow_node
  belongs_to :parent_subagent_run, class_name: "SubagentRun", optional: true
  belongs_to :terminal_summary_artifact, class_name: "WorkflowArtifact", optional: true

  has_many :child_subagent_runs,
    class_name: "SubagentRun",
    foreign_key: :parent_subagent_run_id,
    dependent: :restrict_with_exception,
    inverse_of: :parent_subagent_run
  has_one :execution_lease, as: :leased_resource, dependent: :restrict_with_exception

  before_validation :default_started_at, on: :create

  validates :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :requested_role_or_slot, presence: true
  validate :metadata_must_be_hash
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :workflow_node_workflow_run_match
  validate :parent_subagent_run_installation_match
  validate :parent_subagent_run_workflow_run_match
  validate :terminal_summary_artifact_installation_match
  validate :terminal_summary_artifact_workflow_run_match
  validate :depth_consistency
  validate :lifecycle_timestamps

  private

  def default_started_at
    self.started_at ||= Time.current if lifecycle_state.present?
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def workflow_node_installation_match
    return if workflow_node.blank?
    return if workflow_node.installation_id == installation_id

    errors.add(:workflow_node, "must belong to the same installation")
  end

  def workflow_node_workflow_run_match
    return if workflow_node.blank? || workflow_run.blank?
    return if workflow_node.workflow_run_id == workflow_run_id

    errors.add(:workflow_node, "must belong to the same workflow run")
  end

  def parent_subagent_run_installation_match
    return if parent_subagent_run.blank?
    return if parent_subagent_run.installation_id == installation_id

    errors.add(:parent_subagent_run, "must belong to the same installation")
  end

  def parent_subagent_run_workflow_run_match
    return if parent_subagent_run.blank? || workflow_run.blank?
    return if parent_subagent_run.workflow_run_id == workflow_run_id

    errors.add(:parent_subagent_run, "must belong to the same workflow run")
  end

  def terminal_summary_artifact_installation_match
    return if terminal_summary_artifact.blank?
    return if terminal_summary_artifact.installation_id == installation_id

    errors.add(:terminal_summary_artifact, "must belong to the same installation")
  end

  def terminal_summary_artifact_workflow_run_match
    return if terminal_summary_artifact.blank? || workflow_run.blank?
    return if terminal_summary_artifact.workflow_run_id == workflow_run_id

    errors.add(:terminal_summary_artifact, "must belong to the same workflow run")
  end

  def depth_consistency
    return if parent_subagent_run.blank?
    return if depth == parent_subagent_run.depth + 1

    errors.add(:depth, "must be parent depth plus one")
  end

  def lifecycle_timestamps
    errors.add(:started_at, "must exist") if started_at.blank?

    if running?
      errors.add(:finished_at, "must be blank while subagent run is running") if finished_at.present?
      return
    end

    errors.add(:finished_at, "must exist when subagent run is not running") if finished_at.blank?
  end
end
