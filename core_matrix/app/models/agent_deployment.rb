require "digest"
require "securerandom"

class AgentDeployment < ApplicationRecord
  enum :health_status,
    {
      healthy: "healthy",
      degraded: "degraded",
      offline: "offline",
      retired: "retired",
    },
    validate: true
  enum :bootstrap_state, { pending: "pending", active: "active", superseded: "superseded" }, validate: true

  belongs_to :installation
  belongs_to :agent_installation
  belongs_to :execution_environment
  belongs_to :active_capability_snapshot, class_name: "CapabilitySnapshot", optional: true

  has_many :capability_snapshots, dependent: :restrict_with_exception

  validates :fingerprint, presence: true, uniqueness: { scope: :installation_id }
  validates :machine_credential_digest, presence: true, uniqueness: true
  validates :protocol_version, presence: true
  validates :sdk_version, presence: true
  validate :endpoint_metadata_must_be_hash
  validate :health_metadata_must_be_hash
  validate :agent_installation_installation_match
  validate :execution_environment_installation_match
  validate :single_active_deployment
  validate :active_capability_snapshot_match

  def self.issue_machine_credential
    loop do
      machine_credential = SecureRandom.hex(32)
      digest = digest_machine_credential(machine_credential)
      return [machine_credential, digest] unless exists?(machine_credential_digest: digest)
    end
  end

  def self.digest_machine_credential(machine_credential)
    Digest::SHA256.hexdigest(machine_credential.to_s)
  end

  def self.find_by_machine_credential(machine_credential)
    return if machine_credential.blank?

    find_by(machine_credential_digest: digest_machine_credential(machine_credential))
  end

  def matches_machine_credential?(machine_credential)
    self.class.digest_machine_credential(machine_credential) == machine_credential_digest
  end

  def capability_snapshot_version
    active_capability_snapshot&.version
  end

  def eligible_for_auto_resume?
    eligible_for_scheduling? && auto_resume_eligible?
  end

  def same_logical_agent?(other_deployment)
    other_deployment.present? && agent_installation_id == other_deployment.agent_installation_id
  end

  def runtime_identity_matches?(turn)
    turn.present? &&
      fingerprint == turn.pinned_deployment_fingerprint &&
      capability_snapshot_version == turn.pinned_capability_snapshot_version
  end

  def preserves_capability_contract?(turn)
    paused_snapshot = turn&.pinned_capability_snapshot
    return false if paused_snapshot.blank? || active_capability_snapshot.blank?

    missing_method_ids = paused_snapshot.protocol_methods.map { |entry| entry["method_id"] } -
      active_capability_snapshot.protocol_methods.map { |entry| entry["method_id"] }
    missing_tool_names = paused_snapshot.tool_catalog.map { |entry| entry["tool_name"] } -
      active_capability_snapshot.tool_catalog.map { |entry| entry["tool_name"] }

    missing_method_ids.empty? && missing_tool_names.empty?
  end

  def eligible_for_scheduling?
    active? &&
      healthy? &&
      agent_installation&.active? &&
      execution_environment&.active? &&
      active_capability_snapshot.present?
  end

  private

  def endpoint_metadata_must_be_hash
    errors.add(:endpoint_metadata, "must be a Hash") unless endpoint_metadata.is_a?(Hash)
  end

  def health_metadata_must_be_hash
    errors.add(:health_metadata, "must be a Hash") unless health_metadata.is_a?(Hash)
  end

  def agent_installation_installation_match
    return if agent_installation.blank?
    return if agent_installation.installation_id == installation_id

    errors.add(:agent_installation, "must belong to the same installation")
  end

  def execution_environment_installation_match
    return if execution_environment.blank?
    return if execution_environment.installation_id == installation_id

    errors.add(:execution_environment, "must belong to the same installation")
  end

  def single_active_deployment
    return unless active?

    conflicting_scope = self.class.where(agent_installation_id: agent_installation_id, bootstrap_state: "active")
    conflicting_scope = conflicting_scope.where.not(id: id) if persisted?
    return unless conflicting_scope.exists?

    errors.add(:agent_installation_id, "already has an active deployment")
  end

  def active_capability_snapshot_match
    return if active_capability_snapshot.blank?
    return if active_capability_snapshot.agent_deployment_id == id

    errors.add(:active_capability_snapshot, "must belong to the deployment")
  end
end
