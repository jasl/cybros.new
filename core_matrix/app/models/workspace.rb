class Workspace < ApplicationRecord
  include HasPublicId

  PRIVACY_VALUES = %w[private].freeze

  belongs_to :installation
  belongs_to :user
  belongs_to :user_program_binding

  has_many :canonical_variables, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :privacy, presence: true, inclusion: { in: PRIVACY_VALUES }
  validate :user_installation_match
  validate :binding_installation_match
  validate :binding_user_match
  validate :single_default_workspace

  def private_workspace? = privacy == "private"

  private

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def binding_installation_match
    return if user_program_binding.blank?
    return if user_program_binding.installation_id == installation_id

    errors.add(:user_program_binding, "must belong to the same installation")
  end

  def binding_user_match
    return if user_program_binding.blank? || user.blank?
    return if user_program_binding.user_id == user_id

    errors.add(:user, "must match the binding owner")
  end

  def single_default_workspace
    return unless is_default?

    conflicting_scope = self.class.where(user_program_binding_id: user_program_binding_id, is_default: true)
    conflicting_scope = conflicting_scope.where.not(id: id) if persisted?
    return unless conflicting_scope.exists?

    errors.add(:user_program_binding_id, "already has a default workspace")
  end
end
