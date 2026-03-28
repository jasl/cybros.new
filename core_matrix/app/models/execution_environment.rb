class ExecutionEnvironment < ApplicationRecord
  include HasPublicId

  TOOL_KINDS = %w[environment_runtime].freeze

  enum :kind, { local: "local", container: "container", remote: "remote" }, validate: true
  enum :lifecycle_state, { active: "active", retired: "retired" }, validate: true

  belongs_to :installation

  has_many :agent_deployments, dependent: :restrict_with_exception
  has_many :conversations, dependent: :restrict_with_exception
  has_many :process_runs, dependent: :restrict_with_exception

  validates :environment_fingerprint, presence: true, uniqueness: { scope: :installation_id }
  validate :connection_metadata_must_be_hash
  validate :capability_payload_must_be_hash
  validate :tool_catalog_must_be_array
  validate :tool_catalog_contract_shape

  def conversation_attachment_upload?
    capability_payload.fetch("conversation_attachment_upload", true) == true
  end

  def as_runtime_plane_payload
    RuntimeCapabilityContract.build(execution_environment: self).environment_plane
  end

  private

  def connection_metadata_must_be_hash
    errors.add(:connection_metadata, "must be a Hash") unless connection_metadata.is_a?(Hash)
  end

  def capability_payload_must_be_hash
    errors.add(:capability_payload, "must be a Hash") unless capability_payload.is_a?(Hash)
  end

  def tool_catalog_must_be_array
    errors.add(:tool_catalog, "must be an Array") unless tool_catalog.is_a?(Array)
  end

  def tool_catalog_contract_shape
    return unless tool_catalog.is_a?(Array)

    tool_catalog.each do |entry|
      unless entry.is_a?(Hash) && entry["tool_name"].to_s.match?(CapabilitySnapshot::METHOD_ID_PATTERN)
        errors.add(:tool_catalog, "must contain snake_case tool_name entries")
        break
      end

      unless TOOL_KINDS.include?(entry["tool_kind"])
        errors.add(:tool_catalog, "must contain supported tool_kind values")
        break
      end
    end
  end
end
