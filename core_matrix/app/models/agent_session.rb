class AgentSession < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state, { active: "active", stale: "stale", closed: "closed" }, validate: true
  enum :health_status,
    {
      pending: "pending",
      healthy: "healthy",
      degraded: "degraded",
      offline: "offline",
      retired: "retired",
    },
    validate: true
  enum :control_activity_state, { idle: "idle", active_control: "active" }, prefix: :control, validate: true

  belongs_to :installation
  belongs_to :agent_program
  belongs_to :agent_program_version

  validates :session_credential_digest, presence: true, uniqueness: true
  validates :session_token_digest, presence: true, uniqueness: true
  validate :endpoint_metadata_must_be_hash
  validate :health_metadata_must_be_hash
  validate :agent_program_installation_match
  validate :agent_program_version_installation_match
  validate :agent_program_version_program_match
  validate :single_active_session

  def self.issue_session_credential
    plaintext = SecureRandom.hex(32)
    [plaintext, digest_session_credential(plaintext)]
  end

  def self.issue_session_token
    plaintext = SecureRandom.hex(32)
    [plaintext, digest_session_token(plaintext)]
  end

  def self.digest_session_credential(plaintext)
    ::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def self.digest_session_token(plaintext)
    ::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def self.find_by_plaintext_session_credential(plaintext)
    find_by(session_credential_digest: digest_session_credential(plaintext))
  end

  def realtime_link_connected?
    endpoint_metadata["realtime_link_connected"] == true
  end

  def scheduling_ready?
    active? && healthy?
  end

  private

  def endpoint_metadata_must_be_hash
    errors.add(:endpoint_metadata, "must be a Hash") unless endpoint_metadata.is_a?(Hash)
  end

  def health_metadata_must_be_hash
    errors.add(:health_metadata, "must be a Hash") unless health_metadata.is_a?(Hash)
  end

  def agent_program_installation_match
    return if agent_program.blank?
    return if agent_program.installation_id == installation_id

    errors.add(:agent_program, "must belong to the same installation")
  end

  def agent_program_version_installation_match
    return if agent_program_version.blank?
    return if agent_program_version.installation_id == installation_id

    errors.add(:agent_program_version, "must belong to the same installation")
  end

  def agent_program_version_program_match
    return if agent_program.blank? || agent_program_version.blank?
    return if agent_program_version.agent_program_id == agent_program_id

    errors.add(:agent_program_version, "must belong to the session agent program")
  end

  def single_active_session
    return unless active?

    scope = self.class.where(agent_program_id: agent_program_id, lifecycle_state: "active")
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:agent_program_id, "already has an active session")
  end
end
