class User < ApplicationRecord
  ROLES = %w[member admin].freeze

  belongs_to :installation
  belongs_to :identity

  has_many :issued_invitations, class_name: "Invitation", foreign_key: :inviter_id, dependent: :restrict_with_exception, inverse_of: :inviter
  has_many :owned_agent_installations, class_name: "AgentInstallation", foreign_key: :owner_user_id, dependent: :nullify, inverse_of: :owner_user
  has_many :sessions, dependent: :destroy
  has_many :user_agent_bindings, dependent: :destroy
  has_many :workspaces, dependent: :destroy

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :display_name, presence: true
  validate :preferences_must_be_hash

  scope :admins, -> { where(role: "admin") }
  scope :active_admins, -> { admins.joins(:identity).merge(Identity.enabled) }

  def admin? = role == "admin"

  def member? = role == "member"

  def admin!
    update!(role: "admin")
  end

  def member!
    update!(role: "member")
  end

  private

  def preferences_must_be_hash
    errors.add(:preferences, "must be a Hash") unless preferences.is_a?(Hash)
  end
end
