class CapabilitySnapshot < ApplicationRecord
  METHOD_ID_PATTERN = /\A[a-z0-9_]+\z/
  TOOL_KINDS = %w[kernel_primitive agent_observation effect_intent].freeze

  belongs_to :agent_deployment, inverse_of: :capability_snapshots

  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :agent_deployment_id }
  validate :protocol_methods_must_be_array
  validate :tool_catalog_must_be_array
  validate :protocol_methods_contract_shape
  validate :tool_catalog_contract_shape
  validate :config_schema_snapshot_must_be_hash
  validate :conversation_override_schema_snapshot_must_be_hash
  validate :default_config_snapshot_must_be_hash

  def readonly? = persisted?

  def as_contract_payload(method_id: nil, reconciliation_report: nil)
    {
      "method_id" => method_id,
      "agent_capabilities_version" => version,
      "protocol_methods" => protocol_methods,
      "tool_catalog" => tool_catalog,
      "config_schema_snapshot" => config_schema_snapshot,
      "conversation_override_schema_snapshot" => conversation_override_schema_snapshot,
      "default_config_snapshot" => default_config_snapshot,
      "reconciliation_report" => reconciliation_report,
    }.compact
  end

  def tool_named?(tool_name)
    tool_catalog.any? { |entry| entry["tool_name"] == tool_name }
  end

  private

  def protocol_methods_must_be_array
    errors.add(:protocol_methods, "must be an Array") unless protocol_methods.is_a?(Array)
  end

  def tool_catalog_must_be_array
    errors.add(:tool_catalog, "must be an Array") unless tool_catalog.is_a?(Array)
  end

  def protocol_methods_contract_shape
    return unless protocol_methods.is_a?(Array)

    protocol_methods.each do |entry|
      unless entry.is_a?(Hash) && entry["method_id"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:protocol_methods, "must contain snake_case method_id entries")
        break
      end
    end
  end

  def tool_catalog_contract_shape
    return unless tool_catalog.is_a?(Array)

    tool_catalog.each do |entry|
      unless entry.is_a?(Hash) && entry["tool_name"].to_s.match?(METHOD_ID_PATTERN)
        errors.add(:tool_catalog, "must contain snake_case tool_name entries")
        break
      end

      unless TOOL_KINDS.include?(entry["tool_kind"])
        errors.add(:tool_catalog, "must contain supported tool_kind values")
        break
      end
    end
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
