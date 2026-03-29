require "digest"
require "securerandom"

class Session < ApplicationRecord
  include HasPublicId
  include HasPlaintextToken

  belongs_to :identity
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :metadata_must_be_hash

  def self.issue_for!(identity:, user:, expires_at:, metadata: {})
    token, digest = generate_unique_token_pair
    create!(
      identity: identity,
      user: user,
      token_digest: digest,
      expires_at: expires_at,
      metadata: metadata
    ).attach_plaintext_token(token)
  end

  def matches_token?(token)
    self.class.digest_token(token) == token_digest
  end

  def revoked? = revoked_at.present?

  def expired? = expires_at <= Time.current

  def active? = !revoked? && !expired?

  def revoke!
    update!(revoked_at: Time.current)
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.generate_unique_token_pair
    loop do
      token = SecureRandom.hex(32)
      digest = digest_token(token)
      return [token, digest] unless exists?(token_digest: digest)
    end
  end
  private_class_method :generate_unique_token_pair

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a Hash") unless metadata.is_a?(Hash)
  end
end
