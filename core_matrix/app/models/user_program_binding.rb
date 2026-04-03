class UserProgramBinding < ApplicationRecord
  belongs_to :installation
  belongs_to :user
  belongs_to :agent_program

  has_many :workspaces, dependent: :restrict_with_exception
  has_one :default_workspace, -> { where(is_default: true) }, class_name: "Workspace"

  validates :user_id, uniqueness: { scope: :agent_program_id }
  validate :preferences_must_be_hash
  validate :user_installation_match
  validate :agent_program_installation_match
  validate :personal_agent_ownership

  private

  def preferences_must_be_hash
    errors.add(:preferences, "must be a Hash") unless preferences.is_a?(Hash)
  end

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def agent_program_installation_match
    return if agent_program.blank?
    return if agent_program.installation_id == installation_id

    errors.add(:agent_program, "must belong to the same installation")
  end

  def personal_agent_ownership
    return if agent_program.blank? || user.blank?
    return unless agent_program.personal?
    return if agent_program.owner_user_id == user_id

    errors.add(:user, "must own the personal agent program")
  end
end
