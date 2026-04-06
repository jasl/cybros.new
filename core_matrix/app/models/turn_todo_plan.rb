class TurnTodoPlan < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  STATUSES = %w[draft active blocked completed canceled failed].freeze

  data_lifecycle_kind! :owner_bound

  belongs_to :installation
  belongs_to :agent_task_run, inverse_of: :turn_todo_plan
  belongs_to :conversation
  belongs_to :turn

  validates :status, :goal_summary, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :counts_payload_must_be_hash
  validate :owner_alignment
  validate :single_active_plan_per_task

  private

  def counts_payload_must_be_hash
    errors.add(:counts_payload, "must be a hash") unless counts_payload.is_a?(Hash)
  end

  def owner_alignment
    if agent_task_run.present? && agent_task_run.installation_id != installation_id
      errors.add(:agent_task_run, "must belong to the same installation")
    end

    if conversation.present? && conversation.installation_id != installation_id
      errors.add(:conversation, "must belong to the same installation")
    end

    if turn.present? && turn.installation_id != installation_id
      errors.add(:turn, "must belong to the same installation")
    end

    if agent_task_run.present? && conversation.present? && agent_task_run.conversation_id != conversation_id
      errors.add(:conversation, "must match the task conversation")
    end

    if agent_task_run.present? && turn.present? && agent_task_run.turn_id != turn_id
      errors.add(:turn, "must match the task turn")
    end
  end

  def single_active_plan_per_task
    return unless status == "active"
    return if agent_task_run.blank?

    existing_scope = self.class.where(agent_task_run_id: agent_task_run_id, status: "active")
    existing_scope = existing_scope.where.not(id: id) if persisted?
    return unless existing_scope.exists?

    errors.add(:agent_task_run, "already has an active turn todo plan")
  end
end
