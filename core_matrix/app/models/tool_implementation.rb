class ToolImplementation < ApplicationRecord
  include HasPublicId

  belongs_to :installation
  belongs_to :tool_definition
  belongs_to :implementation_source

  has_many :tool_bindings, dependent: :restrict_with_exception
  has_many :tool_invocations, dependent: :restrict_with_exception

  validates :implementation_ref, presence: true
  validates :idempotency_policy, presence: true
  validate :default_uniqueness_within_tool_definition
  validate :installation_matches_tool_definition
  validate :installation_matches_implementation_source
  validate :input_schema_must_be_hash
  validate :result_schema_must_be_hash
  validate :metadata_must_be_hash

  private

  def installation_matches_tool_definition
    return if tool_definition.blank? || tool_definition.installation_id == installation_id

    errors.add(:installation, "must match the tool definition installation")
  end

  def installation_matches_implementation_source
    return if implementation_source.blank? || implementation_source.installation_id == installation_id

    errors.add(:installation, "must match the implementation source installation")
  end

  def input_schema_must_be_hash
    errors.add(:input_schema, "must be a hash") unless input_schema.is_a?(Hash)
  end

  def result_schema_must_be_hash
    errors.add(:result_schema, "must be a hash") unless result_schema.is_a?(Hash)
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def default_uniqueness_within_tool_definition
    return unless default_for_snapshot?
    return if tool_definition.blank?

    existing_default = tool_definition.tool_implementations.where(default_for_snapshot: true).where.not(id: id).exists?
    errors.add(:default_for_snapshot, "must be unique within a tool definition") if existing_default
  end
end
