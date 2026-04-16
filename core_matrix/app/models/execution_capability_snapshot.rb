class ExecutionCapabilitySnapshot < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  data_lifecycle_kind! :shared_frozen_contract

  belongs_to :installation
  belongs_to :agent_definition_version
  belongs_to :tool_surface_document, class_name: "JsonDocument"
  belongs_to :subagent_connection, optional: true
  belongs_to :parent_subagent_connection, class_name: "SubagentConnection", optional: true
  belongs_to :owner_conversation, class_name: "Conversation", optional: true

  validates :fingerprint, presence: true, uniqueness: { scope: :installation_id }
  validate :agent_definition_version_installation_match
  validate :subagent_policy_snapshot_must_be_hash

  def tool_surface
    payload = tool_surface_document&.payload
    payload.is_a?(Array) ? payload.deep_dup : []
  end

  def agent_definition_fingerprint
    agent_definition_version&.definition_fingerprint
  end

  private

  def agent_definition_version_installation_match
    return if agent_definition_version.blank? || agent_definition_version.installation_id == installation_id

    errors.add(:agent_definition_version, "must belong to the same installation")
  end

  def subagent_policy_snapshot_must_be_hash
    errors.add(:subagent_policy_snapshot, "must be a hash") unless subagent_policy_snapshot.is_a?(Hash)
  end
end
