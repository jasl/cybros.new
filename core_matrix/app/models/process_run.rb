class ProcessRun < ApplicationRecord
  include HasPublicId
  include ClosableRuntimeResource

  enum :kind,
    {
      background_service: "background_service",
    },
    validate: true
  enum :lifecycle_state,
    {
      starting: "starting",
      running: "running",
      stopped: "stopped",
      failed: "failed",
      lost: "lost",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_node
  belongs_to :execution_epoch, class_name: "ConversationExecutionEpoch"
  belongs_to :execution_runtime, class_name: "ExecutionRuntime"
  belongs_to :conversation
  belongs_to :turn
  belongs_to :origin_message, class_name: "Message", optional: true

  has_one :execution_lease, as: :leased_resource, dependent: :restrict_with_exception

  before_validation :default_started_at, on: :create
  before_validation :default_execution_epoch

  validates :command_line, presence: true
  validate :metadata_must_be_hash
  validate :workflow_node_installation_match
  validate :execution_epoch_installation_match
  validate :execution_runtime_installation_match
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :origin_message_installation_match
  validate :execution_epoch_conversation_match
  validate :execution_epoch_runtime_match
  validate :workflow_node_turn_match
  validate :workflow_node_conversation_match
  validate :turn_execution_runtime_match
  validate :turn_execution_epoch_match
  validate :origin_message_turn_match
  validate :origin_message_conversation_match
  validate :timeout_rules
  validate :lifecycle_timestamps

  def workflow_run
    workflow_node&.workflow_run
  end

  private

  def default_started_at
    self.started_at ||= Time.current if lifecycle_state.present?
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def workflow_node_installation_match
    return if workflow_node.blank?
    return if workflow_node.installation_id == installation_id

    errors.add(:workflow_node, "must belong to the same installation")
  end

  def execution_epoch_installation_match
    return if execution_epoch.blank?
    return if execution_epoch.installation_id == installation_id

    errors.add(:execution_epoch, "must belong to the same installation")
  end

  def execution_runtime_installation_match
    return if execution_runtime.blank?
    return if execution_runtime.installation_id == installation_id

    errors.add(:execution_runtime, "must belong to the same installation")
  end

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

  def origin_message_installation_match
    return if origin_message.blank?
    return if origin_message.installation_id == installation_id

    errors.add(:origin_message, "must belong to the same installation")
  end

  def execution_epoch_conversation_match
    return if execution_epoch.blank? || conversation.blank?
    return if execution_epoch.conversation_id == conversation_id

    errors.add(:execution_epoch, "must belong to the same conversation")
  end

  def execution_epoch_runtime_match
    return if execution_epoch.blank? || execution_runtime.blank?
    return if execution_epoch.execution_runtime_id == execution_runtime_id

    errors.add(:execution_runtime, "must match the execution epoch runtime")
  end

  def workflow_node_turn_match
    return if workflow_node.blank? || turn.blank?
    return if workflow_node.workflow_run.turn_id == turn_id

    errors.add(:turn, "must match the workflow run turn")
  end

  def workflow_node_conversation_match
    return if workflow_node.blank? || conversation.blank?
    return if workflow_node.workflow_run.conversation_id == conversation_id

    errors.add(:conversation, "must match the workflow run conversation")
  end

  def turn_execution_runtime_match
    return if turn.blank? || execution_runtime.blank?
    return if turn.execution_runtime_id == execution_runtime_id

    errors.add(:execution_runtime, "must match the turn execution runtime")
  end

  def turn_execution_epoch_match
    return if turn.blank? || execution_epoch.blank?
    return if turn.execution_epoch_id == execution_epoch_id

    errors.add(:execution_epoch, "must match the turn execution epoch")
  end

  def origin_message_turn_match
    return if origin_message.blank? || turn.blank?
    return if origin_message.turn_id == turn_id

    errors.add(:origin_message, "must belong to the same turn")
  end

  def origin_message_conversation_match
    return if origin_message.blank? || conversation.blank?
    return if origin_message.conversation_id == conversation_id

    errors.add(:origin_message, "must belong to the same conversation")
  end

  def timeout_rules
    errors.add(:timeout_seconds, "must be blank for background_service process runs") if timeout_seconds.present?
  end

  def lifecycle_timestamps
    errors.add(:started_at, "must exist") if started_at.blank?

    if starting? || running?
      errors.add(:ended_at, "must be blank while process run is running") if ended_at.present?
      return
    end

    errors.add(:ended_at, "must exist when process run is not running") if ended_at.blank?
  end

  def default_execution_epoch
    return if execution_epoch.present?
    return unless turn.present?

    self.execution_epoch = turn.execution_epoch
  end
end
