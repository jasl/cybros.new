class ExecutionRuntimeVersion < ApplicationRecord
  include HasPublicId

  METHOD_ID_PATTERN = /\A[a-z0-9_]+\z/

  belongs_to :installation
  belongs_to :execution_runtime
  belongs_to :capability_payload_document, class_name: "JsonDocument"
  belongs_to :tool_catalog_document, class_name: "JsonDocument"
  belongs_to :reflected_host_metadata_document, class_name: "JsonDocument", optional: true

  has_many :execution_runtime_connections, dependent: :restrict_with_exception
  has_many :turns, dependent: :restrict_with_exception
  has_many :execution_contracts, dependent: :restrict_with_exception

  validates :content_fingerprint, presence: true, uniqueness: { scope: :execution_runtime_id }
  validates :version, presence: true, uniqueness: { scope: :execution_runtime_id }
  validates :execution_runtime_fingerprint, presence: true
  validates :protocol_version, presence: true
  validates :sdk_version, presence: true
  validates :kind, presence: true
  validate :execution_runtime_installation_match
  validate :document_installation_match
  validate :tool_catalog_contract_shape

  def capability_payload
    payload = capability_payload_document&.payload
    payload.is_a?(Hash) ? payload.deep_dup : {}
  end

  def tool_catalog
    payload = tool_catalog_document&.payload
    payload.is_a?(Array) ? payload.deep_dup : []
  end

  def reflected_host_metadata
    payload = reflected_host_metadata_document&.payload
    payload.is_a?(Hash) ? payload.deep_dup : {}
  end

  private

  def execution_runtime_installation_match
    return if execution_runtime.blank? || execution_runtime.installation_id == installation_id

    errors.add(:execution_runtime, "must belong to the same installation")
  end

  def document_installation_match
    [capability_payload_document, tool_catalog_document, reflected_host_metadata_document].compact.each do |document|
      next if document.installation_id == installation_id

      attribute =
        case document
        when capability_payload_document then :capability_payload_document
        when tool_catalog_document then :tool_catalog_document
        else :reflected_host_metadata_document
        end
      errors.add(attribute, "must belong to the same installation")
    end
  end

  def tool_catalog_contract_shape
    tool_catalog.each do |entry|
      unless entry.is_a?(Hash) && entry["tool_name"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:tool_catalog_document, "must contain snake_case tool_name entries")
        break
      end
    end
  end
end
