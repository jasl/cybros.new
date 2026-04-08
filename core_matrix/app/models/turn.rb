class Turn < ApplicationRecord
  include HasPublicId

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
  belongs_to :agent_program_version
  belongs_to :executor_program, class_name: "ExecutorProgram", optional: true
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
  validates :pinned_program_version_fingerprint, presence: true
  validate :origin_payload_must_be_hash
  validate :feature_policy_snapshot_must_be_hash
  validate :resolved_config_snapshot_must_be_hash
  validate :resolved_model_selection_snapshot_must_be_hash
  validate :conversation_installation_match
  validate :agent_program_version_installation_match
  validate :executor_program_installation_match
  validate :agent_program_version_conversation_match
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

  def pinned_capability_snapshot_version
    1
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

  def agent_program_version_installation_match
    return if agent_program_version.blank?
    return if agent_program_version.installation_id == installation_id

    errors.add(:agent_program_version, "must belong to the same installation")
  end

  def executor_program_installation_match
    return if executor_program.blank?
    return if executor_program.installation_id == installation_id

    errors.add(:executor_program, "must belong to the same installation")
  end

  def agent_program_version_conversation_match
    return if conversation.blank? || agent_program_version.blank?
    return if agent_program_version.agent_program_id == conversation.agent_program_id

    errors.add(:agent_program_version, "must belong to the conversation agent program")
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
