class Turn < ApplicationRecord
  include HasPublicId

  attr_accessor :pinned_agent_definition_fingerprint

  enum :lifecycle_state,
    {
      queued: "queued",
      active: "active",
      waiting: "waiting",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true
  enum :origin_kind,
    {
      manual_user: "manual_user",
      automation_schedule: "automation_schedule",
      automation_webhook: "automation_webhook",
      system_internal: "system_internal",
    },
    validate: true
  enum :cancellation_reason_kind,
    {
      conversation_deleted: "conversation_deleted",
      conversation_archived: "conversation_archived",
      turn_interrupted: "turn_interrupted",
    },
    validate: { allow_nil: true }

  belongs_to :installation
  belongs_to :conversation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :agent_definition_version
  belongs_to :execution_epoch, class_name: "ConversationExecutionEpoch"
  belongs_to :execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :execution_runtime_version, class_name: "ExecutionRuntimeVersion", optional: true
  belongs_to :execution_contract, optional: true
  belongs_to :selected_input_message, class_name: "Message", optional: true
  belongs_to :selected_output_message, class_name: "Message", optional: true

  has_many :messages, dependent: :restrict_with_exception
  has_many :conversation_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :conversation_supervision_feed_entries,
    foreign_key: :target_turn_id,
    dependent: :restrict_with_exception,
    inverse_of: :target_turn
  has_one :workflow_run, dependent: :restrict_with_exception

  validates :sequence, uniqueness: { scope: :conversation_id }
  validates :agent_config_content_fingerprint, presence: true
  validates :agent_config_version,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validate :origin_payload_must_be_hash
  validate :feature_policy_snapshot_must_be_hash
  validate :resolved_config_snapshot_must_be_hash
  validate :resolved_model_selection_snapshot_must_be_hash
  validate :conversation_installation_match
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :agent_definition_version_installation_match
  validate :execution_epoch_installation_match
  validate :execution_epoch_conversation_match
  validate :execution_runtime_installation_match
  validate :execution_runtime_version_installation_match
  validate :execution_runtime_epoch_match
  validate :conversation_user_match
  validate :conversation_workspace_match
  validate :conversation_agent_match
  validate :execution_runtime_version_runtime_match
  validate :agent_definition_version_conversation_match
  validate :selected_input_message_rules
  validate :selected_output_message_rules
  validate :selected_output_lineage_rules
  validate :cancellation_request_pairing

  before_validation :default_feature_policy_snapshot

  def terminal?
    completed? || failed? || canceled?
  end

  def normalized_selector
    resolved_model_selection_snapshot["normalized_selector"]
  end

  def resolved_provider_handle
    resolved_model_selection_snapshot["resolved_provider_handle"]
  end

  def resolved_model_ref
    resolved_model_selection_snapshot["resolved_model_ref"]
  end

  def resolved_role_name
    resolved_model_selection_snapshot["resolved_role_name"]
  end

  def recovery_selector
    normalized_selector.presence || "role:main"
  end

  def execution_snapshot
    @execution_snapshot ||= TurnExecutionSnapshot.new(turn: self)
  end

  def pinned_agent_definition_fingerprint
    agent_definition_version&.definition_fingerprint
  end

  def feature_enabled?(feature_id)
    Array(feature_policy_snapshot["enabled_feature_ids"]).include?(feature_id.to_s)
  end

  def during_generation_input_policy
    feature_policy_snapshot["during_generation_input_policy"]
  end

  def tail_in_active_timeline?
    return false if canceled?

    conversation.turns
      .where("sequence > ?", sequence)
      .where.not(lifecycle_state: "canceled")
      .none?
  end

  private

  def origin_payload_must_be_hash
    errors.add(:origin_payload, "must be a hash") unless origin_payload.is_a?(Hash)
  end

  def feature_policy_snapshot_must_be_hash
    return if feature_policy_snapshot.is_a?(Hash)

    errors.add(:feature_policy_snapshot, "must be a hash")
  end

  def resolved_config_snapshot_must_be_hash
    errors.add(:resolved_config_snapshot, "must be a hash") unless resolved_config_snapshot.is_a?(Hash)
  end

  def resolved_model_selection_snapshot_must_be_hash
    return if resolved_model_selection_snapshot.is_a?(Hash)

    errors.add(:resolved_model_selection_snapshot, "must be a hash")
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def agent_definition_version_installation_match
    return if agent_definition_version.blank?
    return if agent_definition_version.installation_id == installation_id

    errors.add(:agent_definition_version, "must belong to the same installation")
  end

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def execution_epoch_installation_match
    return if execution_epoch.blank?
    return if execution_epoch.installation_id == installation_id

    errors.add(:execution_epoch, "must belong to the same installation")
  end

  def execution_epoch_conversation_match
    return if execution_epoch.blank? || conversation.blank?
    return if execution_epoch.conversation_id == conversation_id

    errors.add(:execution_epoch, "must belong to the same conversation")
  end

  def execution_runtime_installation_match
    return if execution_runtime.blank?
    return if execution_runtime.installation_id == installation_id

    errors.add(:execution_runtime, "must belong to the same installation")
  end

  def execution_runtime_version_installation_match
    return if execution_runtime_version.blank?
    return if execution_runtime_version.installation_id == installation_id

    errors.add(:execution_runtime_version, "must belong to the same installation")
  end

  def execution_runtime_version_runtime_match
    return if execution_runtime.blank? || execution_runtime_version.blank?
    return if execution_runtime_version.execution_runtime_id == execution_runtime_id

    errors.add(:execution_runtime_version, "must belong to the selected execution runtime")
  end

  def execution_runtime_epoch_match
    return if execution_epoch.blank? || execution_runtime.blank?
    return if execution_epoch.execution_runtime_id == execution_runtime_id

    errors.add(:execution_runtime, "must match the execution epoch runtime")
  end

  def conversation_user_match
    return if conversation.blank? || user.blank?
    return if conversation.user_id == user_id

    errors.add(:user, "must match the conversation owner")
  end

  def conversation_workspace_match
    return if conversation.blank? || workspace.blank?
    return if conversation.workspace_id == workspace_id

    errors.add(:workspace, "must match the conversation workspace")
  end

  def conversation_agent_match
    return if conversation.blank? || agent.blank?
    return if conversation.agent_id == agent_id

    errors.add(:agent, "must match the conversation agent")
  end

  def agent_definition_version_conversation_match
    return if conversation.blank? || agent_definition_version.blank?
    return if agent_definition_version.agent_id == conversation.agent_id

    errors.add(:agent_definition_version, "must belong to the conversation agent")
  end

  def selected_input_message_rules
    return if selected_input_message.blank?

    errors.add(:selected_input_message, "must belong to the same turn") unless selected_input_message.turn_id == id
    errors.add(:selected_input_message, "must be an input message") unless selected_input_message.input?
  end

  def selected_output_message_rules
    return if selected_output_message.blank?

    errors.add(:selected_output_message, "must belong to the same turn") unless selected_output_message.turn_id == id
    errors.add(:selected_output_message, "must be an output message") unless selected_output_message.output?
  end

  def selected_output_lineage_rules
    return if selected_input_message.blank? || selected_output_message.blank?
    return if selected_output_message.source_input_message_id == selected_input_message_id

    errors.add(:selected_output_message, "must belong to the selected input lineage")
  end

  def cancellation_request_pairing
    if cancellation_reason_kind.present? && cancellation_requested_at.blank?
      errors.add(:cancellation_requested_at, "must exist when cancellation reason is present")
    end

    if cancellation_reason_kind.blank? && cancellation_requested_at.present?
      errors.add(:cancellation_reason_kind, "must exist when cancellation has been requested")
    end
  end

  def default_feature_policy_snapshot
    return unless conversation.present?
    return unless feature_policy_snapshot.blank?

    self.feature_policy_snapshot = conversation.feature_policy_snapshot
  end
end
