class WorkflowNodeEvent < ApplicationRecord
  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workflow_node

  validates :event_kind, presence: true
  validates :ordinal,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :workflow_node_id }
  validate :payload_must_be_hash
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :workflow_node_workflow_run_match

  private

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
end
