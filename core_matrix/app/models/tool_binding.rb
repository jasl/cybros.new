class ToolBinding < ApplicationRecord
  include HasPublicId

  enum :binding_reason,
    {
      snapshot_default: "snapshot_default",
      recovery_override: "recovery_override",
      explicit_override: "explicit_override",
    },
    validate: true

  belongs_to :installation
  belongs_to :agent_task_run, optional: true
  belongs_to :workflow_node, optional: true
  belongs_to :tool_definition
  belongs_to :tool_implementation

  has_many :tool_invocations, dependent: :destroy

  validate :execution_subject_present
  validate :installation_matches_task
  validate :installation_matches_workflow_node
  validate :installation_matches_tool_definition
  validate :installation_matches_tool_implementation
  validate :workflow_node_matches_task_projection
  validate :tool_definition_matches_execution_projection
  validate :tool_implementation_matches_tool_definition
  validate :tool_definition_unique_within_owner
  validate :binding_payload_must_be_hash

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

  def installation_matches_tool_definition
    return if tool_definition.blank? || tool_definition.installation_id == installation_id

    errors.add(:installation, "must match the tool definition installation")
  end

  def installation_matches_tool_implementation
    return if tool_implementation.blank? || tool_implementation.installation_id == installation_id

    errors.add(:installation, "must match the tool implementation installation")
  end

  def workflow_node_matches_task_projection
    return if workflow_node.blank? || agent_task_run.blank?
    return if agent_task_run.workflow_node_id == workflow_node_id

    errors.add(:workflow_node, "must match the task workflow node")
  end

  def tool_implementation_matches_tool_definition
    return if tool_definition.blank? || tool_implementation.blank?
    return if tool_implementation.tool_definition_id == tool_definition_id

    errors.add(:tool_implementation, "must belong to the bound tool definition")
  end

  def tool_definition_matches_execution_projection
    turn_record = agent_task_run&.turn || workflow_node&.turn
    return if tool_definition.blank? || turn_record.blank?

    expected_program_version_id = turn_record.agent_program_version_id
    return if expected_program_version_id.blank?
    return if tool_definition.agent_program_version_id == expected_program_version_id

    errors.add(:tool_definition, "must belong to the execution agent program version")
  end

  def binding_payload_must_be_hash
    errors.add(:binding_payload, "must be a hash") unless binding_payload.is_a?(Hash)
  end

  def tool_definition_unique_within_owner
    return if tool_definition.blank?

    if agent_task_run.present?
      duplicate_exists = agent_task_run.tool_bindings.where(tool_definition: tool_definition).where.not(id: id).exists?
      errors.add(:tool_definition, "has already been bound for the task") if duplicate_exists
      return
    end

    return if workflow_node.blank?

    duplicate_exists = ToolBinding.where(
      workflow_node: workflow_node,
      agent_task_run_id: nil,
      tool_definition: tool_definition
    ).where.not(id: id).exists?
    errors.add(:tool_definition, "has already been bound for the workflow node") if duplicate_exists
  end
end
