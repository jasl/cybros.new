class ExecutionRuntimeConnection < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state, { active: "active", stale: "stale", closed: "closed" }, validate: true

  belongs_to :installation
  belongs_to :execution_runtime
  belongs_to :execution_runtime_version

  validates :connection_credential_digest, presence: true, uniqueness: true
  validates :connection_token_digest, presence: true, uniqueness: true
  validate :endpoint_metadata_must_be_hash
  validate :execution_runtime_installation_match
  validate :execution_runtime_version_installation_match
  validate :execution_runtime_version_runtime_match
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

  private

  def endpoint_metadata_must_be_hash
    errors.add(:endpoint_metadata, "must be a Hash") unless endpoint_metadata.is_a?(Hash)
  end

  def execution_runtime_installation_match
    return if execution_runtime.blank?
    return if execution_runtime.installation_id == installation_id

    errors.add(:execution_runtime, "must belong to the same installation")
  end

  def execution_runtime_version_installation_match
    return if execution_runtime_version.blank?
    return if execution_runtime_version.installation_id == installation_id

    errors.add(:execution_runtime_version, "must belong to the same installation")
  end

  def execution_runtime_version_runtime_match
    return if execution_runtime.blank? || execution_runtime_version.blank?
    return if execution_runtime_version.execution_runtime_id == execution_runtime_id

    errors.add(:execution_runtime_version, "must belong to the connected execution runtime")
  end

  def single_active_connection
    return unless active?

    scope = self.class.where(execution_runtime_id: execution_runtime_id, lifecycle_state: "active")
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:execution_runtime_id, "already has an active connection")
  end
end
