require "digest"
require "securerandom"

class Publication < ApplicationRecord
  include HasPublicId

  attr_reader :plaintext_access_token

  enum :visibility_mode,
    {
      disabled: "disabled",
      internal_public: "internal_public",
      external_public: "external_public",
    },
    validate: true

  belongs_to :installation
  belongs_to :conversation
  belongs_to :owner_user, class_name: "User"

  has_many :publication_access_events, dependent: :restrict_with_exception

  validates :slug, presence: true, uniqueness: true
  validates :access_token_digest, presence: true, uniqueness: true
  validate :conversation_installation_match
  validate :owner_user_installation_match
  validate :owner_user_matches_conversation_workspace

  def self.digest_access_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_plaintext_access_token(token)
    return if token.blank?

    find_by(access_token_digest: digest_access_token(token))
  end

  def self.issue_slug
    loop do
      slug = "pub-#{SecureRandom.hex(8)}"
      return slug unless exists?(slug: slug)
    end
  end

  def self.issue_access_token_pair
    loop do
      token = SecureRandom.hex(24)
      digest = digest_access_token(token)
      return [token, digest] unless exists?(access_token_digest: digest)
    end
  end

  def matches_access_token?(token)
    self.class.digest_access_token(token) == access_token_digest
  end

  def active?
    !disabled? && published_at.present? && revoked_at.blank?
  end

  def revoked? = revoked_at.present?

  def remember_plaintext_access_token!(token)
    @plaintext_access_token = token
    self
  end

  private

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def owner_user_installation_match
    return if owner_user.blank?
    return if owner_user.installation_id == installation_id

    errors.add(:owner_user, "must belong to the same installation")
  end

  def owner_user_matches_conversation_workspace
    return if owner_user.blank? || conversation.blank?
    return if owner_user_id == conversation.workspace.user_id

    errors.add(:owner_user, "must match the conversation workspace owner")
  end
end
