class ExecutionProfileFact < ApplicationRecord
  enum :fact_kind,
    {
      provider_request: "provider_request",
      tool_call: "tool_call",
      subagent_outcome: "subagent_outcome",
      approval_wait: "approval_wait",
      process_failure: "process_failure",
    },
    validate: true

  belongs_to :installation
  belongs_to :user, optional: true
  belongs_to :workspace, optional: true

  validates :fact_key, presence: true
  validates :occurred_at, presence: true
  validates :count_value, :duration_ms,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validate :metadata_must_be_hash
  validate :user_installation_match
  validate :workspace_installation_match

  private

  def metadata_must_be_hash
    return if metadata.is_a?(Hash)

    errors.add(:metadata, "must be a hash")
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
end
