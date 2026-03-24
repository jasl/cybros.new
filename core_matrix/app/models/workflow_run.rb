class WorkflowRun < ApplicationRecord
  enum :lifecycle_state,
    {
      active: "active",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn

  has_many :workflow_nodes, dependent: :restrict_with_exception
  has_many :workflow_edges, dependent: :restrict_with_exception

  validates :turn_id, uniqueness: true
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :turn_conversation_match
  validate :one_active_workflow_per_conversation

  private

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

  def turn_conversation_match
    return if turn.blank? || conversation.blank?
    return if turn.conversation_id == conversation_id

    errors.add(:conversation, "must match the turn conversation")
  end

  def one_active_workflow_per_conversation
    return unless active?

    existing_active = self.class
      .where(conversation_id: conversation_id, lifecycle_state: "active")
      .where.not(id: id)
      .exists?
    return unless existing_active

    errors.add(:conversation, "already has an active workflow")
  end
end
