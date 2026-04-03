class AgentProgram < ApplicationRecord
  include HasPublicId

  enum :visibility, { personal: "personal", global: "global" }, validate: true
  enum :lifecycle_state, { active: "active", retired: "retired" }, validate: true

  belongs_to :installation
  belongs_to :owner_user, class_name: "User", optional: true, inverse_of: :owned_agent_programs
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true

  has_many :agent_enrollments, dependent: :restrict_with_exception
  has_many :agent_program_versions, dependent: :restrict_with_exception
  has_many :user_program_bindings, dependent: :restrict_with_exception
  has_many :conversations, dependent: :restrict_with_exception
  has_many :agent_sessions, dependent: :restrict_with_exception
  has_one :active_agent_session,
    -> { where(lifecycle_state: "active") },
    class_name: "AgentSession",
    dependent: :restrict_with_exception

  validates :key, presence: true, uniqueness: { scope: :installation_id }
  validates :display_name, presence: true
  validate :owner_user_requirements
  validate :owner_user_installation_match
  validate :default_execution_runtime_installation_match

  def current_agent_program_version
    active_agent_session&.agent_program_version
  end

  private

  def owner_user_requirements
    errors.add(:owner_user, "must exist") if personal? && owner_user.blank?
    errors.add(:owner_user, "must be blank for global visibility") if global? && owner_user.present?
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
end
