class AgentConnection < ApplicationRecord
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
  belongs_to :agent
  belongs_to :agent_snapshot

  validates :connection_credential_digest, presence: true, uniqueness: true
  validates :connection_token_digest, presence: true, uniqueness: true
  validate :endpoint_metadata_must_be_hash
  validate :health_metadata_must_be_hash
  validate :agent_installation_match
  validate :agent_snapshot_installation_match
  validate :agent_snapshot_program_match
  validate :single_active_connection

  def self.issue_connection_credential
    plaintext = SecureRandom.hex(32)
    [plaintext, digest_connection_credential(plaintext)]
  end

  def self.issue_connection_token
    plaintext = SecureRandom.hex(32)
    [plaintext, digest_connection_token(plaintext)]
  end

  def self.digest_connection_credential(plaintext)
    ::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def self.digest_connection_token(plaintext)
    ::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def self.find_by_plaintext_connection_credential(plaintext)
    find_by(connection_credential_digest: digest_connection_credential(plaintext))
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

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def agent_snapshot_installation_match
    return if agent_snapshot.blank?
    return if agent_snapshot.installation_id == installation_id

    errors.add(:agent_snapshot, "must belong to the same installation")
  end

  def agent_snapshot_program_match
    return if agent.blank? || agent_snapshot.blank?
    return if agent_snapshot.agent_id == agent_id

    errors.add(:agent_snapshot, "must belong to the connected agent")
  end

  def single_active_connection
    return unless active?

    scope = self.class.where(agent_id: agent_id, lifecycle_state: "active")
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:agent_id, "already has an active connection")
  end
end
