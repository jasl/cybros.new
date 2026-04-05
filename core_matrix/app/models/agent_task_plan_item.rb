class AgentTaskPlanItem < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  STATUSES = %w[pending in_progress completed blocked canceled].freeze

  data_lifecycle_kind! :owner_bound

  belongs_to :installation
  belongs_to :agent_task_run
  belongs_to :parent_plan_item, class_name: "AgentTaskPlanItem", optional: true
  belongs_to :delegated_subagent_session, class_name: "SubagentSession", optional: true

  has_many :child_plan_items,
    class_name: "AgentTaskPlanItem",
    foreign_key: :parent_plan_item_id,
    dependent: :restrict_with_exception,
    inverse_of: :parent_plan_item

  validates :item_key, :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :details_payload_must_be_hash
  validate :installation_alignment
  validate :single_in_progress_item_per_task

  private

  def details_payload_must_be_hash
    errors.add(:details_payload, "must be a hash") unless details_payload.is_a?(Hash)
  end

  def installation_alignment
    if agent_task_run.present? && agent_task_run.installation_id != installation_id
      errors.add(:agent_task_run, "must belong to the same installation")
    end

    if parent_plan_item.present? && parent_plan_item.agent_task_run_id != agent_task_run_id
      errors.add(:parent_plan_item, "must belong to the same task")
    end

    if delegated_subagent_session.present? && delegated_subagent_session.installation_id != installation_id
      errors.add(:delegated_subagent_session, "must belong to the same installation")
    end
  end

  def single_in_progress_item_per_task
    return unless status == "in_progress"
    return if agent_task_run.blank?

    existing_scope = self.class.where(agent_task_run_id: agent_task_run_id, status: "in_progress")
    existing_scope = existing_scope.where.not(id: id) if persisted?
    return unless existing_scope.exists?

    errors.add(:status, "only one plan item may be in progress per task")
  end
end
