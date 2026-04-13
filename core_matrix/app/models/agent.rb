class Agent < ApplicationRecord
  include HasPublicId

  enum :visibility, { public: "public", private: "private" }, prefix: :visibility, validate: true
  enum :provisioning_origin, { system: "system", user_created: "user_created" }, prefix: :provisioning_origin, validate: true
  enum :lifecycle_state, { active: "active", retired: "retired" }, validate: true

  belongs_to :installation
  belongs_to :owner_user, class_name: "User", optional: true, inverse_of: :owned_agents
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :current_agent_definition_version, class_name: "AgentDefinitionVersion", optional: true
  belongs_to :published_agent_definition_version, class_name: "AgentDefinitionVersion", optional: true

  has_many :onboarding_sessions, foreign_key: :target_agent_id, dependent: :restrict_with_exception
  has_many :agent_definition_versions, dependent: :restrict_with_exception
  has_one :agent_config_state, dependent: :restrict_with_exception
  has_many :user_agent_bindings, dependent: :restrict_with_exception
  has_many :conversations, dependent: :restrict_with_exception
  has_many :agent_connections, dependent: :restrict_with_exception
  has_one :active_agent_connection,
    -> { where(lifecycle_state: "active") },
    class_name: "AgentConnection",
    dependent: :restrict_with_exception

  validates :key, presence: true, uniqueness: { scope: :installation_id }
  validates :display_name, presence: true
  validate :owner_user_requirements
  validate :owner_user_installation_match
  validate :default_execution_runtime_installation_match
  validate :current_agent_definition_version_installation_match
  validate :current_agent_definition_version_agent_match

  def self.visible_to_user(user)
    return none if user.blank?

    where(installation_id: user.installation_id, lifecycle_state: "active")
      .where(
        "visibility = :public_visibility OR (visibility = :private_visibility AND owner_user_id = :user_id)",
        public_visibility: visibilities[:public],
        private_visibility: visibilities[:private],
        user_id: user.id
      )
  end

  def current_agent_definition_version
    association(:current_agent_definition_version).reader ||
      active_agent_connection&.agent_definition_version ||
      published_agent_definition_version
  end

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

  def default_execution_runtime_installation_match
    return if default_execution_runtime.blank?
    return if default_execution_runtime.installation_id == installation_id

    errors.add(:default_execution_runtime, "must belong to the same installation")
  end

  def current_agent_definition_version_installation_match
    return if self[:current_agent_definition_version_id].blank? || association(:current_agent_definition_version).reader.blank?
    return if association(:current_agent_definition_version).reader.installation_id == installation_id

    errors.add(:current_agent_definition_version, "must belong to the same installation")
  end

  def current_agent_definition_version_agent_match
    version = association(:current_agent_definition_version).reader
    return if version.blank?
    return if version.agent_id == id

    errors.add(:current_agent_definition_version, "must belong to this agent")
  end
end
