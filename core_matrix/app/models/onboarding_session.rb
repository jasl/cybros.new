require "digest"
require "securerandom"

class OnboardingSession < ApplicationRecord
  include HasPublicId
  include HasPlaintextToken

  TARGET_KINDS = %w[agent execution_runtime].freeze
  STATUSES = %w[issued registered revoked closed].freeze

  belongs_to :installation
  belongs_to :target_agent, class_name: "Agent", optional: true
  belongs_to :target_execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :issued_by_user, class_name: "User", optional: true

  validates :target_kind, presence: true, inclusion: { in: TARGET_KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :token_digest, presence: true, uniqueness: true
  validates :issued_at, presence: true
  validates :expires_at, presence: true
  validate :target_requirements
  validate :installation_matches_target_agent
  validate :installation_matches_target_execution_runtime
  validate :installation_matches_issuer

  def self.issue!(installation:, target_kind:, target_agent: nil, target_execution_runtime: nil, issued_by_user: nil, expires_at:, issued_at: Time.current)
    token, digest = generate_unique_token_pair

    create!(
      installation: installation,
      target_kind: target_kind,
      target_agent: target_agent,
      target_execution_runtime: target_execution_runtime,
      issued_by_user: issued_by_user,
      token_digest: digest,
      status: "issued",
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

  def close!
    update!(closed_at: Time.current, status: "closed")
  end

  def revoke!
    update!(revoked_at: Time.current, status: "revoked")
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

  def target_requirements
    case target_kind
    when "agent"
      errors.add(:target_agent, "must exist") if target_agent.blank?
      errors.add(:target_execution_runtime, "must be blank for agent onboarding") if target_execution_runtime.present?
    when "execution_runtime"
      errors.add(:target_agent, "must be blank for execution runtime onboarding") if target_agent.present?
    end
  end

  def installation_matches_target_agent
    return if target_agent.blank? || target_agent.installation_id == installation_id

    errors.add(:target_agent, "must belong to the same installation")
  end

  def installation_matches_target_execution_runtime
    return if target_execution_runtime.blank? || target_execution_runtime.installation_id == installation_id

    errors.add(:target_execution_runtime, "must belong to the same installation")
  end

  def installation_matches_issuer
    return if issued_by_user.blank? || issued_by_user.installation_id == installation_id

    errors.add(:issued_by_user, "must belong to the same installation")
  end
end
