class WorkflowEdge < ApplicationRecord
  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :from_node, class_name: "WorkflowNode"
  belongs_to :to_node, class_name: "WorkflowNode"

  validates :ordinal,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: [:workflow_run_id, :from_node_id] }
  validates :to_node_id, uniqueness: { scope: [:workflow_run_id, :from_node_id] }
  validate :workflow_run_installation_match
  validate :node_installation_match
  validate :same_workflow_integrity
  validate :no_self_loop

  private

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def node_installation_match
    if from_node.present? && from_node.installation_id != installation_id
      errors.add(:from_node, "must belong to the same installation")
    end
    if to_node.present? && to_node.installation_id != installation_id
      errors.add(:to_node, "must belong to the same installation")
    end
  end

  def same_workflow_integrity
    return if workflow_run.blank?

    if from_node.present? && from_node.workflow_run_id != workflow_run_id
      errors.add(:from_node, "must belong to the same workflow")
    end
    if to_node.present? && to_node.workflow_run_id != workflow_run_id
      errors.add(:to_node, "must belong to the same workflow")
    end
  end

  def no_self_loop
    return if from_node_id.blank? || to_node_id.blank?
    return unless from_node_id == to_node_id

    errors.add(:to_node, "must differ from the from node")
  end
end
