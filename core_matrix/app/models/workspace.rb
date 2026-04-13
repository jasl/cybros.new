class Workspace < ApplicationRecord
  include HasPublicId

  PRIVACY_VALUES = %w[private].freeze

  belongs_to :installation
  belongs_to :user
  belongs_to :agent
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true

  has_many :canonical_variables, dependent: :restrict_with_exception
  has_one :workspace_policy, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :privacy, presence: true, inclusion: { in: PRIVACY_VALUES }
  validate :user_installation_match
  validate :agent_installation_match
  validate :default_execution_runtime_installation_match
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

  def user_agent_binding
    @user_agent_binding ||= begin
      return if installation_id.blank? || user_id.blank? || agent_id.blank?

      UserAgentBinding.find_by(
        installation_id: installation_id,
        user_id: user_id,
        agent_id: agent_id
      )
    end
  end

  def user_agent_binding=(binding)
    @user_agent_binding = binding
    self.installation ||= binding.installation
    self.user ||= binding.user
    self.agent ||= binding.agent
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
