class ExecutionContract < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  data_lifecycle_kind! :shared_frozen_contract

  belongs_to :installation
  belongs_to :turn
  belongs_to :agent_definition_version
  belongs_to :execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :execution_runtime_version, class_name: "ExecutionRuntimeVersion", optional: true
  belongs_to :selected_input_message, class_name: "Message", optional: true
  belongs_to :selected_output_message, class_name: "Message", optional: true
  belongs_to :workspace_agent_global_instructions_document, class_name: "JsonDocument", optional: true
  belongs_to :workspace_agent_profile_settings_document, class_name: "JsonDocument", optional: true
  belongs_to :execution_capability_snapshot
  belongs_to :execution_context_snapshot

  validates :turn_id, uniqueness: true
  validate :provider_context_must_be_hash
  validate :turn_origin_must_be_hash
  validate :attachment_manifest_must_be_array
  validate :model_input_attachments_must_be_array
  validate :attachment_diagnostics_must_be_array
  validate :workspace_agent_global_instructions_document_installation_match
  validate :workspace_agent_global_instructions_document_kind_match
  validate :workspace_agent_profile_settings_document_installation_match
  validate :workspace_agent_profile_settings_document_kind_match

  def identity
    {
      "user_id" => turn.conversation.workspace.user.public_id,
      "workspace_id" => turn.conversation.workspace.public_id,
      "conversation_id" => turn.conversation.public_id,
      "turn_id" => turn.public_id,
      "selected_input_message_id" => selected_input_message&.public_id,
      "execution_runtime_id" => execution_runtime&.public_id,
      "execution_runtime_version_id" => execution_runtime_version&.public_id,
      "agent_definition_version_id" => agent_definition_version.public_id,
    }
  end

  def task
    {
      "conversation_id" => turn.conversation.public_id,
      "turn_id" => turn.public_id,
      "selected_input_message_id" => selected_input_message&.public_id,
      "selected_output_message_id" => selected_output_message&.public_id,
      "origin_kind" => turn.origin_kind,
      "origin_payload" => turn.origin_payload,
      "source_ref_type" => turn.source_ref_type,
      "source_ref_id" => turn.source_ref_id,
    }.compact
  end

  def provider_context_payload
    provider_context.deep_dup
  end

  def turn_origin_payload
    turn_origin.deep_dup
  end

  def attachment_manifest_payload
    Array(attachment_manifest).map(&:deep_dup)
  end

  def model_input_attachments_payload
    Array(model_input_attachments).map(&:deep_dup)
  end

  def attachment_diagnostics_payload
    Array(attachment_diagnostics).map(&:deep_dup)
  end

  def workspace_agent_global_instructions
    payload = workspace_agent_global_instructions_document&.payload
    return unless workspace_agent_global_instructions_document&.document_kind == "workspace_agent_global_instructions"
    return unless payload.is_a?(Hash)

    payload["global_instructions"].presence
  end

  def workspace_agent_profile_settings
    payload = workspace_agent_profile_settings_document&.payload
    return {} unless workspace_agent_profile_settings_document&.document_kind == "workspace_agent_profile_settings"
    return {} unless payload.is_a?(Hash)

    value = payload["profile_settings"]
    value.is_a?(Hash) ? value.deep_dup : {}
  end

  private

  def provider_context_must_be_hash
    errors.add(:provider_context, "must be a hash") unless provider_context.is_a?(Hash)
  end

  def turn_origin_must_be_hash
    errors.add(:turn_origin, "must be a hash") unless turn_origin.is_a?(Hash)
  end

  def attachment_manifest_must_be_array
    errors.add(:attachment_manifest, "must be an array") unless attachment_manifest.is_a?(Array)
  end

  def model_input_attachments_must_be_array
    errors.add(:model_input_attachments, "must be an array") unless model_input_attachments.is_a?(Array)
  end

  def attachment_diagnostics_must_be_array
    errors.add(:attachment_diagnostics, "must be an array") unless attachment_diagnostics.is_a?(Array)
  end

  def workspace_agent_global_instructions_document_installation_match
    return if workspace_agent_global_instructions_document.blank?
    return if workspace_agent_global_instructions_document.installation_id == installation_id

    errors.add(:workspace_agent_global_instructions_document, "must belong to the same installation")
  end

  def workspace_agent_global_instructions_document_kind_match
    return if workspace_agent_global_instructions_document.blank?
    return if workspace_agent_global_instructions_document.document_kind == "workspace_agent_global_instructions"

    errors.add(:workspace_agent_global_instructions_document, "must have document kind workspace_agent_global_instructions")
  end

  def workspace_agent_profile_settings_document_installation_match
    return if workspace_agent_profile_settings_document.blank?
    return if workspace_agent_profile_settings_document.installation_id == installation_id

    errors.add(:workspace_agent_profile_settings_document, "must belong to the same installation")
  end

  def workspace_agent_profile_settings_document_kind_match
    return if workspace_agent_profile_settings_document.blank?
    return if workspace_agent_profile_settings_document.document_kind == "workspace_agent_profile_settings"

    errors.add(:workspace_agent_profile_settings_document, "must have document kind workspace_agent_profile_settings")
  end
end
