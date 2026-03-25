class WorkflowNodeEvent < ApplicationRecord
  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workflow_node
  belongs_to :workspace
  belongs_to :conversation
  belongs_to :turn

  enum :presentation_policy,
    {
      internal_only: "internal_only",
      ops_trackable: "ops_trackable",
      user_projectable: "user_projectable",
    },
    validate: true

  before_validation :default_projection_fields_from_workflow_node

  validates :event_kind, presence: true
  validates :ordinal,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :workflow_node_id }
  validate :payload_must_be_hash
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :workflow_node_workflow_run_match
  validate :projection_integrity

  private

  def default_projection_fields_from_workflow_node
    return if workflow_node.blank?

    self.workspace ||= workflow_node.workspace
    self.conversation ||= workflow_node.conversation
    self.turn ||= workflow_node.turn
    self.workflow_node_key ||= workflow_node.node_key
    self.workflow_node_ordinal ||= workflow_node.ordinal
    self.presentation_policy ||= workflow_node.presentation_policy
  end

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
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

  def projection_integrity
    return if workflow_node.blank?

    if workspace.present? && workflow_node.workspace_id != workspace_id
      errors.add(:workspace, "must match the workflow node workspace")
    end
    if conversation.present? && workflow_node.conversation_id != conversation_id
      errors.add(:conversation, "must match the workflow node conversation")
    end
    if turn.present? && workflow_node.turn_id != turn_id
      errors.add(:turn, "must match the workflow node turn")
    end
    if workflow_node_key.present? && workflow_node.node_key != workflow_node_key
      errors.add(:workflow_node_key, "must match the workflow node key")
    end
    if !workflow_node_ordinal.nil? && workflow_node.ordinal != workflow_node_ordinal
      errors.add(:workflow_node_ordinal, "must match the workflow node ordinal")
    end
    if presentation_policy.present? && workflow_node.presentation_policy != presentation_policy
      errors.add(:presentation_policy, "must match the workflow node presentation policy")
    end
  end
end
