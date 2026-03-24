class Turn < ApplicationRecord
  enum :lifecycle_state,
    {
      queued: "queued",
      active: "active",
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

  belongs_to :installation
  belongs_to :conversation
  belongs_to :agent_deployment
  belongs_to :selected_input_message, class_name: "Message", optional: true
  belongs_to :selected_output_message, class_name: "Message", optional: true

  has_many :messages, dependent: :restrict_with_exception
  has_many :conversation_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_one :workflow_run, dependent: :restrict_with_exception

  validates :sequence, uniqueness: { scope: :conversation_id }
  validates :pinned_deployment_fingerprint, presence: true
  validate :origin_payload_must_be_hash
  validate :resolved_config_snapshot_must_be_hash
  validate :resolved_model_selection_snapshot_must_be_hash
  validate :conversation_installation_match
  validate :agent_deployment_installation_match
  validate :selected_input_message_rules
  validate :selected_output_message_rules

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

  def pinned_capability_snapshot_id
    resolved_model_selection_snapshot["capability_snapshot_id"]
  end

  def pinned_capability_snapshot
    CapabilitySnapshot.find_by(id: pinned_capability_snapshot_id)
  end

  def pinned_capability_snapshot_version
    pinned_capability_snapshot&.version
  end

  def recovery_selector
    normalized_selector.presence || "role:main"
  end

  def effective_config_snapshot
    return resolved_config_snapshot["config"] if resolved_config_snapshot.key?("config")

    resolved_config_snapshot
  end

  def execution_context
    resolved_config_snapshot.fetch("execution_context", {})
  end

  def execution_identity
    execution_context.fetch("identity", {})
  end

  def turn_origin_context
    execution_context.fetch("turn_origin", {})
  end

  def context_messages
    execution_context.fetch("context_messages", [])
  end

  def context_imports
    execution_context.fetch("context_imports", [])
  end

  def attachment_manifest
    execution_context.fetch("attachment_manifest", [])
  end

  def runtime_attachment_manifest
    execution_context.fetch("runtime_attachment_manifest", [])
  end

  def model_input_attachments
    execution_context.fetch("model_input_attachments", [])
  end

  def attachment_diagnostics
    execution_context.fetch("attachment_diagnostics", [])
  end

  def tail_in_active_timeline?
    conversation.turns
      .where("sequence > ?", sequence)
      .where.not(lifecycle_state: "canceled")
      .none?
  end

  private

  def origin_payload_must_be_hash
    errors.add(:origin_payload, "must be a hash") unless origin_payload.is_a?(Hash)
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

  def agent_deployment_installation_match
    return if agent_deployment.blank?
    return if agent_deployment.installation_id == installation_id

    errors.add(:agent_deployment, "must belong to the same installation")
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
end
