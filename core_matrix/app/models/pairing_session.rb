require "digest"
require "securerandom"

class PairingSession < ApplicationRecord
  include HasPublicId
  include HasPlaintextToken

  belongs_to :installation
  belongs_to :agent

  validates :token_digest, presence: true, uniqueness: true
  validates :issued_at, presence: true
  validates :expires_at, presence: true
  validate :agent_installation_match

  def self.issue!(installation:, agent:, expires_at:, issued_at: Time.current)
    token, digest = generate_unique_token_pair
    create!(
      installation: installation,
      agent: agent,
      token_digest: digest,
      issued_at: issued_at,
      expires_at: expires_at
    ).attach_plaintext_token(token)
  end

  def self.find_by_plaintext_token(token)
    return if token.blank?

    find_by(token_digest: digest_token(token))
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def matches_token?(token)
    self.class.digest_token(token) == token_digest
  end

  def expired?
    expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def closed?
    closed_at.present?
  end

  def active?
    !expired? && !revoked? && !closed?
  end

  def mark_runtime_registered!
    update!(runtime_registered_at: Time.current, last_used_at: Time.current)
  end

  def mark_agent_registered!
    update!(agent_registered_at: Time.current, last_used_at: Time.current)
  end

  def close!
    update!(closed_at: Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def self.generate_unique_token_pair
    loop do
      token = SecureRandom.hex(32)
      digest = digest_token(token)
      return [token, digest] unless exists?(token_digest: digest)
    end
  end
  private_class_method :generate_unique_token_pair

  def agent_installation_match
    return if agent.blank? || agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end
end
