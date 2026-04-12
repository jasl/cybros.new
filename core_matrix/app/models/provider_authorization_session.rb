require "base64"
require "digest"
require "securerandom"

class ProviderAuthorizationSession < ApplicationRecord
  include HasPublicId

  STATUSES = %w[pending completed revoked].freeze

  attr_reader :plaintext_state, :plaintext_pkce_verifier

  encrypts :pkce_verifier

  belongs_to :installation
  belongs_to :issued_by_user, class_name: "User", optional: true

  validates :provider_handle, presence: true
  validates :state_digest, presence: true, uniqueness: true
  validates :pkce_verifier, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :issued_at, presence: true
  validates :expires_at, presence: true
  validate :installation_matches_issuer

  def self.issue!(installation:, provider_handle:, issued_by_user: nil, expires_at:, issued_at: Time.current)
    state, state_digest = generate_unique_state_pair
    pkce_verifier = generate_pkce_verifier

    create!(
      installation: installation,
      provider_handle: provider_handle,
      issued_by_user: issued_by_user,
      state_digest: state_digest,
      pkce_verifier: pkce_verifier,
      status: "pending",
      issued_at: issued_at,
      expires_at: expires_at
    ).tap do |authorization_session|
      authorization_session.remember_plaintext_state!(state)
      authorization_session.remember_plaintext_pkce_verifier!(pkce_verifier)
    end
  end

  def self.find_by_plaintext_state(state)
    return if state.blank?

    find_by(state_digest: digest_state(state))
  end

  def self.digest_state(state)
    Digest::SHA256.hexdigest(state.to_s)
  end

  def self.code_challenge_for(verifier)
    digest = Digest::SHA256.digest(verifier.to_s)
    Base64.urlsafe_encode64(digest, padding: false)
  end

  def matches_state?(state)
    self.class.digest_state(state) == state_digest
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

  def remember_plaintext_state!(state)
    @plaintext_state = state
    self
  end

  def remember_plaintext_pkce_verifier!(verifier)
    @plaintext_pkce_verifier = verifier
    self
  end

  private

  def self.generate_unique_state_pair
    loop do
      state = SecureRandom.urlsafe_base64(32, false)
      digest = digest_state(state)
      return [state, digest] unless exists?(state_digest: digest)
    end
  end
  private_class_method :generate_unique_state_pair

  def self.generate_pkce_verifier
    SecureRandom.urlsafe_base64(64, false)
  end
  private_class_method :generate_pkce_verifier

  def installation_matches_issuer
    return if issued_by_user.blank? || issued_by_user.installation_id == installation_id

    errors.add(:issued_by_user, "must belong to the same installation")
  end
end
