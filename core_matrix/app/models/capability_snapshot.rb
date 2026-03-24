class CapabilitySnapshot < ApplicationRecord
  belongs_to :agent_deployment, inverse_of: :capability_snapshots

  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :agent_deployment_id }
  validate :protocol_methods_must_be_array
  validate :tool_catalog_must_be_array
  validate :config_schema_snapshot_must_be_hash
  validate :conversation_override_schema_snapshot_must_be_hash
  validate :default_config_snapshot_must_be_hash

  def readonly? = persisted?

  private

  def protocol_methods_must_be_array
    errors.add(:protocol_methods, "must be an Array") unless protocol_methods.is_a?(Array)
  end

  def tool_catalog_must_be_array
    errors.add(:tool_catalog, "must be an Array") unless tool_catalog.is_a?(Array)
  end

  def config_schema_snapshot_must_be_hash
    errors.add(:config_schema_snapshot, "must be a Hash") unless config_schema_snapshot.is_a?(Hash)
  end

  def conversation_override_schema_snapshot_must_be_hash
    errors.add(:conversation_override_schema_snapshot, "must be a Hash") unless conversation_override_schema_snapshot.is_a?(Hash)
  end

  def default_config_snapshot_must_be_hash
    errors.add(:default_config_snapshot, "must be a Hash") unless default_config_snapshot.is_a?(Hash)
  end
end
