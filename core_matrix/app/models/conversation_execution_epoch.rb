class ConversationExecutionEpoch < ApplicationRecord
  include HasPublicId

  self.table_name = "conversation_execution_epochs"

  enum :lifecycle_state,
    {
      active: "active",
      superseded: "superseded",
      failed: "failed",
    },
    validate: true

  belongs_to :installation
  belongs_to :conversation
  belongs_to :execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :source_execution_epoch, class_name: "ConversationExecutionEpoch", optional: true

  has_many :next_execution_epochs,
    class_name: "ConversationExecutionEpoch",
    foreign_key: :source_execution_epoch_id,
    dependent: :restrict_with_exception,
    inverse_of: :source_execution_epoch
  has_many :turns, foreign_key: :execution_epoch_id, dependent: :restrict_with_exception
  has_many :process_runs, foreign_key: :execution_epoch_id, dependent: :restrict_with_exception
  has_many :current_conversations,
    class_name: "Conversation",
    foreign_key: :current_execution_epoch_id,
    dependent: :restrict_with_exception,
    inverse_of: :current_execution_epoch

  validates :sequence, uniqueness: { scope: :conversation_id }
  validate :continuity_payload_must_be_hash
  validate :conversation_installation_match
  validate :execution_runtime_installation_match
  validate :source_execution_epoch_installation_match
  validate :source_execution_epoch_conversation_match

  before_validation :default_opened_at, on: :create

  private

  def continuity_payload_must_be_hash
    errors.add(:continuity_payload, "must be a hash") unless continuity_payload.is_a?(Hash)
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def execution_runtime_installation_match
    return if execution_runtime.blank?
    return if execution_runtime.installation_id == installation_id

    errors.add(:execution_runtime, "must belong to the same installation")
  end

  def source_execution_epoch_installation_match
    return if source_execution_epoch.blank?
    return if source_execution_epoch.installation_id == installation_id

    errors.add(:source_execution_epoch, "must belong to the same installation")
  end

  def source_execution_epoch_conversation_match
    return if source_execution_epoch.blank? || conversation.blank?
    return if source_execution_epoch.conversation_id == conversation_id

    errors.add(:source_execution_epoch, "must belong to the same conversation")
  end

  def default_opened_at
    self.opened_at ||= Time.current
  end
end
