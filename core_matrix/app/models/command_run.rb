class CommandRun < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state,
    {
      starting: "starting",
      running: "running",
      completed: "completed",
      failed: "failed",
      interrupted: "interrupted",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :agent_task_run, optional: true
  belongs_to :workflow_node, optional: true
  belongs_to :tool_invocation

  before_validation :default_started_at, on: :create

  validates :command_line, presence: true
  validate :metadata_must_be_hash
  validate :execution_subject_present
  validate :installation_matches_task
  validate :installation_matches_workflow_node
  validate :installation_matches_tool_invocation
  validate :tool_invocation_matches_execution_subject
  validate :tool_invocation_tool_name
  validate :lifecycle_timestamps

  private

  def execution_subject_present
    return if agent_task_run.present? || workflow_node.present?

    errors.add(:base, "must belong to an agent task run or workflow node")
  end

  def default_started_at
    self.started_at ||= Time.current if lifecycle_state.present?
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def installation_matches_task
    return if agent_task_run.blank? || agent_task_run.installation_id == installation_id

    errors.add(:installation, "must match the task installation")
  end

  def installation_matches_workflow_node
    return if workflow_node.blank? || workflow_node.installation_id == installation_id

    errors.add(:installation, "must match the workflow node installation")
  end

  def installation_matches_tool_invocation
    return if tool_invocation.blank? || tool_invocation.installation_id == installation_id

    errors.add(:installation, "must match the tool invocation installation")
  end

  def tool_invocation_matches_execution_subject
    return if tool_invocation.blank?

    if tool_invocation.agent_task_run_id != agent_task_run_id
      errors.add(:agent_task_run, "must match the tool invocation task")
    end

    if tool_invocation.workflow_node_id != workflow_node_id
      errors.add(:workflow_node, "must match the tool invocation workflow node")
    end
  end

  def tool_invocation_tool_name
    return if tool_invocation.blank?
    return if tool_invocation.tool_definition.tool_name == "exec_command"

    errors.add(:tool_invocation, "must target the exec_command tool")
  end

  def lifecycle_timestamps
    errors.add(:started_at, "must exist") if started_at.blank?

    if starting? || running?
      errors.add(:ended_at, "must be blank while command run is running") if ended_at.present?
      return
    end

    errors.add(:ended_at, "must exist when command run is terminal") if ended_at.blank?
  end
end
