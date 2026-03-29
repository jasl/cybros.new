class CapabilitySnapshot < ApplicationRecord
  METHOD_ID_PATTERN = /\A[a-z0-9_]+\z/
  TOOL_KINDS = %w[kernel_primitive agent_observation effect_intent].freeze
  RESERVED_CORE_MATRIX_PREFIX = "core_matrix__".freeze

  belongs_to :agent_deployment, inverse_of: :capability_snapshots
  has_many :tool_definitions, dependent: :restrict_with_exception

  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :agent_deployment_id }
  validate :protocol_methods_must_be_array
  validate :tool_catalog_must_be_array
  validate :protocol_methods_contract_shape
  validate :tool_catalog_contract_shape
  validate :tool_catalog_reserved_prefix_policy
  validate :profile_catalog_must_be_hash
  validate :config_schema_snapshot_must_be_hash
  validate :conversation_override_schema_snapshot_must_be_hash
  validate :default_config_snapshot_must_be_hash

  def readonly? = persisted?

  def tool_named?(tool_name)
    tool_catalog.any? { |entry| entry["tool_name"] == tool_name }
  end

  def matches_runtime_capability_contract?(runtime_capability_contract)
    comparable_contract_payload ==
      self.class.comparable_contract_payload(runtime_capability_contract)
  end

  def comparable_contract_payload
    self.class.comparable_contract_payload(self)
  end

  def self.comparable_contract_payload(source)
    contract = case source
    when RuntimeCapabilityContract
      source
    when CapabilitySnapshot
      RuntimeCapabilityContract.build(capability_snapshot: source)
    else
      raise ArgumentError, "unsupported capability contract source #{source.class.name}"
    end

    {
      "protocol_methods" => contract.protocol_methods,
      "tool_catalog" => contract.agent_tool_catalog,
      "profile_catalog" => contract.profile_catalog,
      "config_schema_snapshot" => contract.config_schema_snapshot,
      "conversation_override_schema_snapshot" => contract.conversation_override_schema_snapshot,
      "default_config_snapshot" => contract.default_config_snapshot,
    }
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

  def tool_catalog_reserved_prefix_policy
    return unless tool_catalog.is_a?(Array)

    tool_catalog.each do |entry|
      next unless entry.is_a?(Hash)
      next unless entry["tool_name"].to_s.start_with?(RESERVED_CORE_MATRIX_PREFIX)
      next if entry["implementation_source"] == "core_matrix"

      errors.add(:tool_catalog, "reserved core_matrix tool names may only be supplied by core_matrix implementations")
      break
    end
  end

  def config_schema_snapshot_must_be_hash
    errors.add(:config_schema_snapshot, "must be a Hash") unless config_schema_snapshot.is_a?(Hash)
  end

  def profile_catalog_must_be_hash
    errors.add(:profile_catalog, "must be a Hash") unless profile_catalog.is_a?(Hash)
  end

  def conversation_override_schema_snapshot_must_be_hash
    errors.add(:conversation_override_schema_snapshot, "must be a Hash") unless conversation_override_schema_snapshot.is_a?(Hash)
  end

  def default_config_snapshot_must_be_hash
    errors.add(:default_config_snapshot, "must be a Hash") unless default_config_snapshot.is_a?(Hash)
  end
end
