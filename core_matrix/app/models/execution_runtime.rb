class ExecutionRuntime < ApplicationRecord
  include HasPublicId

  alias_attribute :execution_runtime_fingerprint, :execution_runtime_fingerprint

  METHOD_ID_PATTERN = /\A[a-z0-9_]+\z/
  TOOL_KINDS = %w[execution_runtime].freeze

  enum :visibility, { public: "public", private: "private" }, prefix: :visibility, validate: true
  enum :provisioning_origin, { system: "system", user_created: "user_created" }, prefix: :provisioning_origin, validate: true
  enum :kind, { local: "local", container: "container", remote: "remote" }, validate: true
  enum :lifecycle_state, { active: "active", retired: "retired" }, validate: true

  belongs_to :installation
  belongs_to :owner_user, class_name: "User", optional: true, inverse_of: :owned_execution_runtimes

  has_many :agents, foreign_key: :default_execution_runtime_id, dependent: :restrict_with_exception
  has_many :turns, foreign_key: :execution_runtime_id, dependent: :restrict_with_exception
  has_many :process_runs, foreign_key: :execution_runtime_id, dependent: :restrict_with_exception
  has_many :execution_runtime_connections, dependent: :restrict_with_exception
  has_one :active_execution_runtime_connection,
    -> { where(lifecycle_state: "active") },
    class_name: "ExecutionRuntimeConnection",
    dependent: :restrict_with_exception

  validates :display_name, presence: true
  validates :execution_runtime_fingerprint, presence: true, uniqueness: { scope: :installation_id }
  validate :owner_user_requirements
  validate :owner_user_installation_match
  validate :connection_metadata_must_be_hash
  validate :capability_payload_must_be_hash
  validate :tool_catalog_must_be_array
  validate :tool_catalog_contract_shape

  private

  def owner_user_requirements
    if visibility_private? && owner_user.blank?
      errors.add(:owner_user, "must exist")
    end

    if visibility_public? && provisioning_origin_user_created? && owner_user.blank?
      errors.add(:owner_user, "must exist for user-created public visibility")
    end

    if provisioning_origin_system?
      errors.add(:visibility, "must be public for system provisioning") unless visibility_public?
      errors.add(:owner_user, "must be blank for system provisioning") if owner_user.present?
    end
  end

  def owner_user_installation_match
    return if owner_user.blank?
    return if owner_user.installation_id == installation_id

    errors.add(:owner_user, "must belong to the same installation")
  end

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
end
