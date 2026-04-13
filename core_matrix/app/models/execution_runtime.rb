class ExecutionRuntime < ApplicationRecord
  include HasPublicId

  enum :visibility, { public: "public", private: "private" }, prefix: :visibility, validate: true
  enum :provisioning_origin, { system: "system", user_created: "user_created" }, prefix: :provisioning_origin, validate: true
  enum :kind, { local: "local", container: "container", remote: "remote" }, validate: true
  enum :lifecycle_state, { active: "active", retired: "retired" }, validate: true

  belongs_to :installation
  belongs_to :owner_user, class_name: "User", optional: true, inverse_of: :owned_execution_runtimes
  belongs_to :current_execution_runtime_version, class_name: "ExecutionRuntimeVersion", optional: true
  belongs_to :published_execution_runtime_version, class_name: "ExecutionRuntimeVersion", optional: true

  has_many :agents, foreign_key: :default_execution_runtime_id, dependent: :restrict_with_exception
  has_many :workspaces, foreign_key: :default_execution_runtime_id, dependent: :restrict_with_exception
  has_many :current_conversations,
    class_name: "Conversation",
    foreign_key: :current_execution_runtime_id,
    dependent: :restrict_with_exception
  has_many :conversation_execution_epochs, dependent: :restrict_with_exception
  has_many :turns, foreign_key: :execution_runtime_id, dependent: :restrict_with_exception
  has_many :process_runs, foreign_key: :execution_runtime_id, dependent: :restrict_with_exception
  has_many :execution_runtime_versions, dependent: :restrict_with_exception
  has_many :execution_runtime_connections, dependent: :restrict_with_exception
  has_many :onboarding_sessions, foreign_key: :target_execution_runtime_id, dependent: :restrict_with_exception
  has_one :active_execution_runtime_connection,
    -> { where(lifecycle_state: "active") },
    class_name: "ExecutionRuntimeConnection",
    dependent: :restrict_with_exception

  validates :display_name, presence: true
  validate :owner_user_requirements
  validate :owner_user_installation_match
  validate :current_execution_runtime_version_installation_match
  validate :current_execution_runtime_version_runtime_match

  def self.visible_to_user(user)
    return none if user.blank?

    where(installation_id: user.installation_id, lifecycle_state: "active")
      .where(
        "\"execution_runtimes\".\"visibility\" = :public_visibility OR (\"execution_runtimes\".\"visibility\" = :private_visibility AND \"execution_runtimes\".\"owner_user_id\" = :user_id)",
        public_visibility: visibilities[:public],
        private_visibility: visibilities[:private],
        user_id: user.id
      )
  end

  def current_execution_runtime_version
    association(:current_execution_runtime_version).reader ||
      active_execution_runtime_connection&.execution_runtime_version ||
      published_execution_runtime_version
  end

  def execution_runtime_fingerprint
    current_execution_runtime_version&.execution_runtime_fingerprint
  end

  def capability_payload
    current_execution_runtime_version&.capability_payload || {}
  end

  def tool_catalog
    current_execution_runtime_version&.tool_catalog || []
  end

  def connection_metadata
    active_execution_runtime_connection&.endpoint_metadata || {}
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

  def current_execution_runtime_version_installation_match
    version = association(:current_execution_runtime_version).reader
    return if version.blank?
    return if version.installation_id == installation_id

    errors.add(:current_execution_runtime_version, "must belong to the same installation")
  end

  def current_execution_runtime_version_runtime_match
    version = association(:current_execution_runtime_version).reader
    return if version.blank?
    return if version.execution_runtime_id == id

    errors.add(:current_execution_runtime_version, "must belong to this execution runtime")
  end
end
