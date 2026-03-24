class Identity < ApplicationRecord
  has_secure_password reset_token: false

  has_one :user, dependent: :destroy
  has_many :sessions, dependent: :destroy

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validate :auth_metadata_must_be_hash

  scope :enabled, -> { where(disabled_at: nil) }

  def disabled? = disabled_at.present?

  def enabled? = !disabled?

  private

  def auth_metadata_must_be_hash
    errors.add(:auth_metadata, "must be a Hash") unless auth_metadata.is_a?(Hash)
  end
end
