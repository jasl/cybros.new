class ProviderAuthorizationSession < ApplicationRecord
  include HasPublicId

  STATUSES = %w[pending completed revoked].freeze

  encrypts :device_auth_id

  belongs_to :installation
  belongs_to :issued_by_user, class_name: "User", optional: true

  validates :provider_handle, presence: true
  validates :device_auth_id, presence: true
  validates :user_code, presence: true
  validates :verification_uri, presence: true
  validates :poll_interval_seconds, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :issued_at, presence: true
  validates :expires_at, presence: true
  validate :installation_matches_issuer

  def self.issue!(installation:, provider_handle:, issued_by_user: nil, device_auth_id:, user_code:, verification_uri:, poll_interval_seconds:, expires_at:, issued_at: Time.current)
    create!(
      installation: installation,
      provider_handle: provider_handle,
      issued_by_user: issued_by_user,
      device_auth_id: device_auth_id,
      user_code: user_code,
      verification_uri: verification_uri,
      poll_interval_seconds: poll_interval_seconds,
      status: "pending",
      issued_at: issued_at,
      expires_at: expires_at
    )
  end

  def expired?
    expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def completed?
    completed_at.present?
  end

  def active?
    !expired? && !revoked? && !completed?
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def revoke!
    update!(status: "revoked", revoked_at: Time.current)
  end

  private

  def installation_matches_issuer
    return if issued_by_user.blank? || issued_by_user.installation_id == installation_id

    errors.add(:issued_by_user, "must belong to the same installation")
  end
end
