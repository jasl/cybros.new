class TurnTodoPlanItem < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  STATUSES = %w[pending in_progress completed blocked canceled failed].freeze

  data_lifecycle_kind! :owner_bound

  belongs_to :turn_todo_plan, inverse_of: :turn_todo_plan_items
  belongs_to :installation
  belongs_to :delegated_subagent_connection, class_name: "SubagentConnection", optional: true

  validates :item_key, :title, :status, :kind, presence: true
  validates :item_key, uniqueness: { scope: :turn_todo_plan_id }
  validates :status, inclusion: { in: STATUSES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :details_payload_must_be_hash
  validate :depends_on_item_keys_must_be_array
  validate :installation_alignment

  private

  def details_payload_must_be_hash
    errors.add(:details_payload, "must be a hash") unless details_payload.is_a?(Hash)
  end

  def depends_on_item_keys_must_be_array
    errors.add(:depends_on_item_keys, "must be an array") unless depends_on_item_keys.is_a?(Array)
  end

  def installation_alignment
    if turn_todo_plan.present? && turn_todo_plan.installation_id != installation_id
      errors.add(:turn_todo_plan, "must belong to the same installation")
    end

    if delegated_subagent_connection.present? && delegated_subagent_connection.installation_id != installation_id
      errors.add(:delegated_subagent_connection, "must belong to the same installation")
    end

    if delegated_subagent_connection.present? &&
        turn_todo_plan.present? &&
        delegated_subagent_connection.owner_conversation_id != turn_todo_plan.conversation_id
      errors.add(:delegated_subagent_connection, "must be owned by the plan conversation")
    end
  end
end
