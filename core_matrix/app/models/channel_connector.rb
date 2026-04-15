class ChannelConnector < ApplicationRecord
  include HasPublicId

  enum :platform, { telegram: "telegram", weixin: "weixin" }, validate: true
  enum :transport_kind, { webhook: "webhook", poller: "poller" }, validate: true
  enum :lifecycle_state,
    {
      active: "active",
      disabled: "disabled",
      disconnected: "disconnected",
    },
    validate: true

  belongs_to :installation
  belongs_to :ingress_binding

  has_many :channel_sessions, dependent: :restrict_with_exception
  has_many :channel_pairing_requests, dependent: :restrict_with_exception
  has_many :channel_inbound_messages, dependent: :restrict_with_exception
  has_many :channel_deliveries, dependent: :restrict_with_exception

  validates :driver, presence: true
  validates :label, presence: true
  validate :ingress_binding_installation_match
  validate :credential_ref_payload_must_be_hash
  validate :config_payload_must_be_hash
  validate :runtime_state_payload_must_be_hash
  validate :single_active_connector

  before_validation :apply_defaults
  before_validation :normalize_payloads

  private

  def apply_defaults
    self.lifecycle_state = "active" if lifecycle_state.blank?
    self.credential_ref_payload = {} if credential_ref_payload.blank?
    self.config_payload = {} if config_payload.blank?
    self.runtime_state_payload = {} if runtime_state_payload.blank?
  end

  def normalize_payloads
    self.credential_ref_payload = credential_ref_payload.deep_stringify_keys if credential_ref_payload.is_a?(Hash)
    self.config_payload = config_payload.deep_stringify_keys if config_payload.is_a?(Hash)
    self.runtime_state_payload = runtime_state_payload.deep_stringify_keys if runtime_state_payload.is_a?(Hash)
  end

  def ingress_binding_installation_match
    return if ingress_binding.blank? || ingress_binding.installation_id == installation_id

    errors.add(:ingress_binding, "must belong to the same installation")
  end

  def credential_ref_payload_must_be_hash
    errors.add(:credential_ref_payload, "must be a hash") unless credential_ref_payload.is_a?(Hash)
  end

  def config_payload_must_be_hash
    errors.add(:config_payload, "must be a hash") unless config_payload.is_a?(Hash)
  end

  def runtime_state_payload_must_be_hash
    errors.add(:runtime_state_payload, "must be a hash") unless runtime_state_payload.is_a?(Hash)
  end

  def single_active_connector
    return unless active?

    scope = self.class.where(ingress_binding_id: ingress_binding_id, lifecycle_state: "active")
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:ingress_binding_id, "already has an active connector")
  end
end
