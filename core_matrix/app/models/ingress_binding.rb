require "digest"
require "securerandom"

class IngressBinding < ApplicationRecord
  include HasPublicId

  KINDS = %w[channel].freeze
  LIFECYCLE_STATES = %w[active disabled].freeze
  DEFAULT_MANUAL_ENTRY_POLICY = {
    "allow_app_entry" => true,
    "allow_external_entry" => true,
  }.freeze

  belongs_to :installation
  belongs_to :workspace_agent
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true

  has_many :channel_connectors, dependent: :restrict_with_exception
  has_many :channel_sessions, dependent: :restrict_with_exception
  has_many :channel_pairing_requests, dependent: :restrict_with_exception
  has_many :channel_inbound_messages, dependent: :restrict_with_exception
  has_many :channel_deliveries, dependent: :restrict_with_exception

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :lifecycle_state, presence: true, inclusion: { in: LIFECYCLE_STATES }
  validates :public_ingress_id, presence: true, uniqueness: true
  validates :ingress_secret_digest, presence: true, uniqueness: true
  validate :workspace_agent_installation_match
  validate :default_execution_runtime_installation_match
  validate :routing_policy_payload_must_be_hash
  validate :manual_entry_policy_must_be_hash

  before_validation :apply_defaults
  before_validation :normalize_payloads

  def self.issue_public_ingress_id
    loop do
      candidate = "ing_#{SecureRandom.hex(16)}"
      return candidate unless exists?(public_ingress_id: candidate)
    end
  end

  def self.digest_ingress_secret(plaintext)
    ::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def self.issue_ingress_secret
    loop do
      plaintext = SecureRandom.hex(32)
      digest = digest_ingress_secret(plaintext)
      return [plaintext, digest] unless exists?(ingress_secret_digest: digest)
    end
  end

  def matches_ingress_secret?(plaintext)
    self.class.digest_ingress_secret(plaintext) == ingress_secret_digest
  end

  private

  def apply_defaults
    self.kind = "channel" if kind.blank?
    self.lifecycle_state = "active" if lifecycle_state.blank?
    self.public_ingress_id = self.class.issue_public_ingress_id if public_ingress_id.blank?

    if ingress_secret_digest.blank?
      _plaintext, digest = self.class.issue_ingress_secret
      self.ingress_secret_digest = digest
    end

    self.routing_policy_payload = {} if routing_policy_payload.blank?
    self.manual_entry_policy = DEFAULT_MANUAL_ENTRY_POLICY.deep_dup if manual_entry_policy.blank?
  end

  def normalize_payloads
    self.routing_policy_payload = routing_policy_payload.deep_stringify_keys if routing_policy_payload.is_a?(Hash)
    self.manual_entry_policy = manual_entry_policy.deep_stringify_keys if manual_entry_policy.is_a?(Hash)
  end

  def workspace_agent_installation_match
    return if workspace_agent.blank? || workspace_agent.installation_id == installation_id

    errors.add(:workspace_agent, "must belong to the same installation")
  end

  def default_execution_runtime_installation_match
    return if default_execution_runtime.blank? || default_execution_runtime.installation_id == installation_id

    errors.add(:default_execution_runtime, "must belong to the same installation")
  end

  def routing_policy_payload_must_be_hash
    errors.add(:routing_policy_payload, "must be a hash") unless routing_policy_payload.is_a?(Hash)
  end

  def manual_entry_policy_must_be_hash
    errors.add(:manual_entry_policy, "must be a hash") unless manual_entry_policy.is_a?(Hash)
  end
end
