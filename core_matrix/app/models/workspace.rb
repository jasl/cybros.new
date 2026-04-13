class Workspace < ApplicationRecord
  include HasPublicId

  TITLE_BOOTSTRAP_MODES = %w[runtime_first embedded_only].freeze
  DEFAULT_TITLE_BOOTSTRAP_CONFIG = {
    "enabled" => true,
    "mode" => "runtime_first",
  }.freeze
  DEFAULT_CONFIG = {
    "metadata" => {
      "title_bootstrap" => DEFAULT_TITLE_BOOTSTRAP_CONFIG,
    },
  }.freeze

  PRIVACY_VALUES = %w[private].freeze

  belongs_to :installation
  belongs_to :user
  belongs_to :agent
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true

  has_many :canonical_variables, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :privacy, presence: true, inclusion: { in: PRIVACY_VALUES }
  validate :user_installation_match
  validate :agent_installation_match
  validate :default_execution_runtime_installation_match
  validate :config_must_be_hash
  validate :title_bootstrap_config_must_be_valid
  validate :disabled_capabilities_must_be_array
  validate :single_default_workspace

  def self.accessible_to_user(user)
    return none if user.blank?

    where(
      installation_id: user.installation_id,
      user_id: user.id,
      privacy: "private"
    ).where(agent_id: Agent.visible_to_user(user).select(:id))
  end

  def private_workspace? = privacy == "private"

  def self.default_config
    DEFAULT_CONFIG.deep_dup
  end

  def config_with_defaults
    self.class.default_config.deep_merge(normalized_config)
  end

  def config_metadata
    metadata = config_with_defaults.fetch("metadata", {})
    metadata.is_a?(Hash) ? metadata : {}
  end

  def title_bootstrap_config
    config_metadata.fetch("title_bootstrap", {})
  end

  def merged_config_with_metadata(metadata:)
    self.class.default_config.deep_merge(
      normalized_config.deep_merge("metadata" => normalized_hash(metadata))
    )
  end

  private

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def default_execution_runtime_installation_match
    return if default_execution_runtime.blank?
    return if default_execution_runtime.installation_id == installation_id

    errors.add(:default_execution_runtime, "must belong to the same installation")
  end

  def config_must_be_hash
    errors.add(:config, "must be a hash") unless config.is_a?(Hash)
  end

  def title_bootstrap_config_must_be_valid
    return unless config.is_a?(Hash)

    metadata = config_with_defaults.fetch("metadata", {})
    unless metadata.is_a?(Hash)
      errors.add(:config, "metadata must be a hash")
      return
    end

    title_bootstrap = metadata.fetch("title_bootstrap", {})
    unless title_bootstrap.is_a?(Hash)
      errors.add(:config, "metadata.title_bootstrap must be a hash")
      return
    end

    enabled = title_bootstrap["enabled"]
    mode = title_bootstrap["mode"]

    errors.add(:config, "metadata.title_bootstrap.enabled must be true or false") unless enabled == true || enabled == false
    errors.add(:config, "metadata.title_bootstrap.mode must be runtime_first or embedded_only") unless TITLE_BOOTSTRAP_MODES.include?(mode)
  end

  def normalized_config
    normalized_hash(config)
  end

  def normalized_hash(value)
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def disabled_capabilities_must_be_array
    errors.add(:disabled_capabilities, "must be an array") unless disabled_capabilities.is_a?(Array)
  end

  def single_default_workspace
    return unless is_default?

    conflicting_scope = self.class.where(
      installation_id: installation_id,
      user_id: user_id,
      agent_id: agent_id,
      is_default: true
    )
    conflicting_scope = conflicting_scope.where.not(id: id) if persisted?
    return unless conflicting_scope.exists?

    errors.add(:agent_id, "already has a default workspace for this user")
  end
end
