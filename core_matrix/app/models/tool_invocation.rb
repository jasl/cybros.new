class ToolInvocation < ApplicationRecord
  include HasPublicId

  enum :status,
    {
      running: "running",
      succeeded: "succeeded",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :agent_task_run, optional: true
  belongs_to :workflow_node, optional: true
  belongs_to :tool_binding
  belongs_to :tool_definition
  belongs_to :tool_implementation

  has_one :command_run, dependent: :destroy

  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validate :execution_subject_present
  validate :installation_matches_task
  validate :installation_matches_workflow_node
  validate :installation_matches_binding
  validate :installation_matches_tool_definition
  validate :installation_matches_tool_implementation
  validate :binding_projection_alignment
  validate :request_payload_must_be_hash
  validate :response_payload_must_be_hash
  validate :error_payload_must_be_hash
  validate :metadata_must_be_hash
  validate :lifecycle_timestamps

  private

  def execution_subject_present
    return if agent_task_run.present? || workflow_node.present?

    errors.add(:base, "must belong to an agent task run or workflow node")
  end

  def installation_matches_task
    return if agent_task_run.blank? || agent_task_run.installation_id == installation_id

    errors.add(:installation, "must match the task installation")
  end

  def installation_matches_workflow_node
    return if workflow_node.blank? || workflow_node.installation_id == installation_id

    errors.add(:installation, "must match the workflow node installation")
  end

  def installation_matches_binding
    return if tool_binding.blank? || tool_binding.installation_id == installation_id

    errors.add(:installation, "must match the tool binding installation")
  end

  def installation_matches_tool_definition
    return if tool_definition.blank? || tool_definition.installation_id == installation_id

    errors.add(:installation, "must match the tool definition installation")
  end

  def installation_matches_tool_implementation
    return if tool_implementation.blank? || tool_implementation.installation_id == installation_id

    errors.add(:installation, "must match the tool implementation installation")
  end

  def binding_projection_alignment
    return if tool_binding.blank?

    if tool_binding.agent_task_run_id != agent_task_run_id
      errors.add(:agent_task_run, "must match the frozen tool binding")
    end

    if tool_binding.workflow_node_id != workflow_node_id
      errors.add(:workflow_node, "must match the frozen tool binding")
    end

    if tool_definition.present? && tool_binding.tool_definition_id != tool_definition_id
      errors.add(:tool_definition, "must match the frozen tool binding")
    end

    if tool_implementation.present? && tool_binding.tool_implementation_id != tool_implementation_id
      errors.add(:tool_implementation, "must match the frozen tool binding")
    end
  end

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def response_payload_must_be_hash
    errors.add(:response_payload, "must be a hash") unless response_payload.is_a?(Hash)
  end

  def error_payload_must_be_hash
    errors.add(:error_payload, "must be a hash") unless error_payload.is_a?(Hash)
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def lifecycle_timestamps
    if running?
      errors.add(:started_at, "must exist while the invocation is running") if started_at.blank?
      errors.add(:finished_at, "must be blank while the invocation is running") if finished_at.present?
      return
    end

    errors.add(:started_at, "must exist when the invocation has started") if started_at.blank?
    errors.add(:finished_at, "must exist when the invocation is terminal") if finished_at.blank?
  end
end
