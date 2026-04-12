class AgentConfigState < ApplicationRecord
  include HasPublicId

  enum :reconciliation_state,
    {
      ready: "ready",
      needs_reconciliation: "needs_reconciliation",
      invalid: "invalid",
    },
    prefix: :reconciliation,
    validate: true

  belongs_to :installation
  belongs_to :agent
  belongs_to :base_agent_definition_version, class_name: "AgentDefinitionVersion"
  belongs_to :override_document, class_name: "JsonDocument", optional: true
  belongs_to :effective_document, class_name: "JsonDocument"

  validates :agent_id, uniqueness: true
  validates :content_fingerprint, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validate :agent_installation_match
  validate :base_agent_definition_version_installation_match
  validate :document_installation_match
  validate :base_agent_definition_version_agent_match

  def override_payload
    payload = override_document&.payload
    payload.is_a?(Hash) ? payload.deep_dup : {}
  end

  def effective_payload
    payload = effective_document&.payload
    payload.is_a?(Hash) ? payload.deep_dup : {}
  end

  private

  def agent_installation_match
    return if agent.blank? || agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def base_agent_definition_version_installation_match
    return if base_agent_definition_version.blank? || base_agent_definition_version.installation_id == installation_id

    errors.add(:base_agent_definition_version, "must belong to the same installation")
  end

  def base_agent_definition_version_agent_match
    return if agent.blank? || base_agent_definition_version.blank?
    return if base_agent_definition_version.agent_id == agent_id

    errors.add(:base_agent_definition_version, "must belong to the same agent")
  end

  def document_installation_match
    [override_document, effective_document].compact.each do |document|
      next if document.installation_id == installation_id

      attribute = document == override_document ? :override_document : :effective_document
      errors.add(attribute, "must belong to the same installation")
    end
  end
end
