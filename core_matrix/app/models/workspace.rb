class Workspace < ApplicationRecord
  include HasPublicId

  PRIVACY_VALUES = %w[private].freeze

  belongs_to :installation
  belongs_to :user
  has_many :canonical_variables, dependent: :restrict_with_exception
  has_many :workspace_agents, dependent: :restrict_with_exception
  has_many :conversations, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :privacy, presence: true, inclusion: { in: PRIVACY_VALUES }
  validate :user_installation_match
  validate :config_must_be_hash
  validate :features_config_must_be_valid
  validate :disabled_capabilities_must_be_array
  validate :single_default_workspace

  def self.accessible_to_user(user)
    return none if user.blank?

    where(
      installation_id: user.installation_id,
      user_id: user.id,
      privacy: "private"
    )
  end

  def private_workspace? = privacy == "private"

  def primary_workspace_agent
    if association(:workspace_agents).loaded?
      workspace_agents.sort_by(&:id).find(&:active?)
    else
      workspace_agents.where(lifecycle_state: "active").order(:id).first
    end
  end

  def agent
    primary_workspace_agent&.agent
  end

  def default_execution_runtime
    primary_workspace_agent&.default_execution_runtime
  end

  def self.default_config
    WorkspaceFeatures::Schema.default_config
  end

  def config_with_defaults
    self.class.default_config.deep_merge(normalized_config)
  end

  def features_config(agent_definition_version: nil)
    WorkspaceFeatures::Resolver.call(
      workspace: self,
      agent_definition_version: agent_definition_version
    )
  end

  def feature_config(name, agent_definition_version: nil)
    features_config(agent_definition_version: agent_definition_version).fetch(name.to_s)
  end

  private

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def config_must_be_hash
    errors.add(:config, "must be a hash") unless config.is_a?(Hash)
  end

  def features_config_must_be_valid
    WorkspaceFeatures::Schema.validation_errors(config).each do |message|
      errors.add(:config, message)
    end
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
      is_default: true
    )
    conflicting_scope = conflicting_scope.where.not(id: id) if persisted?
    return unless conflicting_scope.exists?

    errors.add(:user_id, "already has a default workspace for this user")
  end
end
