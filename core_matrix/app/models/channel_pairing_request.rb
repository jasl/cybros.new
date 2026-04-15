require "digest"
require "securerandom"

class ChannelPairingRequest < ApplicationRecord
  include HasPublicId

  enum :lifecycle_state,
    {
      pending: "pending",
      approved: "approved",
      rejected: "rejected",
      expired: "expired",
    },
    validate: true

  belongs_to :installation
  belongs_to :ingress_binding
  belongs_to :channel_connector
  belongs_to :channel_session, optional: true

  validates :platform_sender_id, presence: true
  validates :pairing_code_digest, presence: true
  validates :expires_at, presence: true
  validate :sender_snapshot_must_be_hash
  validate :ingress_binding_installation_match
  validate :channel_connector_installation_match
  validate :channel_session_installation_match
  validate :connector_binding_match
  validate :session_connector_match
  validate :single_pending_request_per_sender

  before_validation :apply_defaults
  before_validation :normalize_sender_snapshot

  def self.digest_pairing_code(plaintext)
    ::Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def self.issue_pairing_code
    loop do
      plaintext = SecureRandom.hex(8)
      digest = digest_pairing_code(plaintext)
      return [plaintext, digest] unless exists?(pairing_code_digest: digest)
    end
  end

  private

  def apply_defaults
    self.lifecycle_state = "pending" if lifecycle_state.blank?
    self.sender_snapshot = {} if sender_snapshot.blank?
  end

  def normalize_sender_snapshot
    self.sender_snapshot = sender_snapshot.deep_stringify_keys if sender_snapshot.is_a?(Hash)
  end

  def sender_snapshot_must_be_hash
    errors.add(:sender_snapshot, "must be a hash") unless sender_snapshot.is_a?(Hash)
  end

  def ingress_binding_installation_match
    return if ingress_binding.blank? || ingress_binding.installation_id == installation_id

    errors.add(:ingress_binding, "must belong to the same installation")
  end

  def channel_connector_installation_match
    return if channel_connector.blank? || channel_connector.installation_id == installation_id

    errors.add(:channel_connector, "must belong to the same installation")
  end

  def channel_session_installation_match
    return if channel_session.blank? || channel_session.installation_id == installation_id

    errors.add(:channel_session, "must belong to the same installation")
  end

  def connector_binding_match
    return if channel_connector.blank? || ingress_binding.blank?
    return if channel_connector.ingress_binding_id == ingress_binding_id

    errors.add(:channel_connector, "must belong to the ingress binding")
  end

  def session_connector_match
    return if channel_session.blank? || channel_connector.blank?
    return if channel_session.channel_connector_id == channel_connector_id

    errors.add(:channel_session, "must belong to the same channel connector")
  end

  def single_pending_request_per_sender
    return unless pending?

    scope = self.class.where(
      channel_connector_id: channel_connector_id,
      platform_sender_id: platform_sender_id,
      lifecycle_state: "pending"
    )
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:platform_sender_id, "already has an active pending pairing request for this connector")
  end
end
