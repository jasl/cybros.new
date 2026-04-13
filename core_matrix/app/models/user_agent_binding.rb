class UserAgentBinding < ApplicationRecord
  belongs_to :installation
  belongs_to :user
  belongs_to :agent

  validates :user_id, uniqueness: { scope: :agent_id }
  validate :preferences_must_be_hash
  validate :user_installation_match
  validate :agent_installation_match
  validate :private_agent_ownership

  def workspaces
    return Workspace.none if installation_id.blank? || user_id.blank? || agent_id.blank?

    Workspace.where(
      installation_id: installation_id,
      user_id: user_id,
      agent_id: agent_id
    )
  end

  def default_workspace
    workspaces.find_by(is_default: true)
  end

  private

  def preferences_must_be_hash
    errors.add(:preferences, "must be a Hash") unless preferences.is_a?(Hash)
  end

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

  def private_agent_ownership
    return if agent.blank? || user.blank?
    return unless agent.visibility_private?
    return if agent.owner_user_id == user_id

    errors.add(:user, "must own the private agent")
  end
end
