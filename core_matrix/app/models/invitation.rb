require "digest"
require "securerandom"

class Invitation < ApplicationRecord
  include HasPublicId

  attr_reader :plaintext_token

  belongs_to :installation
  belongs_to :inviter, class_name: "User", inverse_of: :issued_invitations

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def self.issue!(installation:, inviter:, email:, expires_at:)
    token, digest = generate_unique_token_pair
    invitation = create!(
      installation: installation,
      inviter: inviter,
      email: email,
      token_digest: digest,
      expires_at: expires_at
    )
    invitation.instance_variable_set(:@plaintext_token, token)
    invitation
  end

  def self.find_by_plaintext_token(token)
    return if token.blank?

    find_by(token_digest: digest_token(token))
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
end
