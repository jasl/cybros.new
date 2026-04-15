class ChannelSession < ApplicationRecord
  include HasPublicId

  enum :platform, { telegram: "telegram", weixin: "weixin" }, validate: true
  enum :binding_state,
    {
      active: "active",
      paused: "paused",
      unbound: "unbound",
    },
    validate: true

  belongs_to :installation
  belongs_to :ingress_binding
  belongs_to :channel_connector
  belongs_to :conversation

  has_many :channel_pairing_requests, dependent: :restrict_with_exception
  has_many :channel_inbound_messages, dependent: :restrict_with_exception
  has_many :channel_deliveries, dependent: :restrict_with_exception

  validates :peer_kind, presence: true
  validates :peer_id, presence: true
  validate :session_metadata_must_be_hash
  validate :ingress_binding_installation_match
  validate :channel_connector_installation_match
  validate :conversation_installation_match
  validate :connector_binding_match
  validate :unique_session_boundary

  before_validation :apply_defaults
  before_validation :normalize_thread_key
  before_validation :normalize_session_metadata

  private

  def apply_defaults
    self.binding_state = "active" if binding_state.blank?
    self.platform = channel_connector&.platform if platform.blank? && channel_connector.present?
    self.session_metadata = {} if session_metadata.blank?
  end

  def normalize_thread_key
    normalized = thread_key.to_s.presence || ""
    self.thread_key = nil if thread_key.blank?
    self.normalized_thread_key = normalized
  end

  def normalize_session_metadata
    self.session_metadata = session_metadata.deep_stringify_keys if session_metadata.is_a?(Hash)
  end

  def session_metadata_must_be_hash
    errors.add(:session_metadata, "must be a hash") unless session_metadata.is_a?(Hash)
  end

  def ingress_binding_installation_match
    return if ingress_binding.blank? || ingress_binding.installation_id == installation_id

    errors.add(:ingress_binding, "must belong to the same installation")
  end

  def channel_connector_installation_match
    return if channel_connector.blank? || channel_connector.installation_id == installation_id

    errors.add(:channel_connector, "must belong to the same installation")
  end

  def conversation_installation_match
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def connector_binding_match
    return if channel_connector.blank? || ingress_binding.blank?
    return if channel_connector.ingress_binding_id == ingress_binding_id

    errors.add(:channel_connector, "must belong to the ingress binding")
  end

  def unique_session_boundary
    scope = self.class.where(
      channel_connector_id: channel_connector_id,
      peer_kind: peer_kind,
      peer_id: peer_id,
      normalized_thread_key: normalized_thread_key
    )
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:normalized_thread_key, "already has a session for this connector boundary")
  end
end
