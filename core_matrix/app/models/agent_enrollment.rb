require "digest"
require "securerandom"

class AgentEnrollment < ApplicationRecord
  include HasPlaintextToken

  belongs_to :installation
  belongs_to :agent_program

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :agent_program_installation_match

  def self.issue!(installation:, agent_program:, expires_at:)
    token, digest = generate_unique_token_pair
    create!(
      installation: installation,
      agent_program: agent_program,
      token_digest: digest,
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

  def consumed? = consumed_at.present?

  def expired? = expires_at <= Time.current

  def active? = !consumed? && !expired?

  def consume!
    update!(consumed_at: Time.current)
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

  def agent_program_installation_match
    return if agent_program.blank?
    return if agent_program.installation_id == installation_id

    errors.add(:agent_program, "must belong to the same installation")
  end
end
