class CommandRun < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state,
    {
      running: "running",
      completed: "completed",
      failed: "failed",
      interrupted: "interrupted",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :agent_task_run
  belongs_to :tool_invocation

  before_validation :default_started_at, on: :create

  validates :command_line, presence: true
  validate :metadata_must_be_hash
  validate :installation_matches_task
  validate :installation_matches_tool_invocation
  validate :tool_invocation_matches_task
  validate :tool_invocation_tool_name
  validate :lifecycle_timestamps

  private

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

  def installation_matches_tool_invocation
    return if tool_invocation.blank? || tool_invocation.installation_id == installation_id

    errors.add(:installation, "must match the tool invocation installation")
  end

  def tool_invocation_matches_task
    return if tool_invocation.blank? || agent_task_run.blank?
    return if tool_invocation.agent_task_run_id == agent_task_run_id

    errors.add(:tool_invocation, "must belong to the same agent task run")
  end

  def tool_invocation_tool_name
    return if tool_invocation.blank?
    return if tool_invocation.tool_definition.tool_name == "exec_command"

    errors.add(:tool_invocation, "must target the exec_command tool")
  end

  def lifecycle_timestamps
    errors.add(:started_at, "must exist") if started_at.blank?

    if running?
      errors.add(:ended_at, "must be blank while command run is running") if ended_at.present?
      return
    end

    errors.add(:ended_at, "must exist when command run is terminal") if ended_at.blank?
  end
end
