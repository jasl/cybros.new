class ChannelDelivery < ApplicationRecord
  include HasPublicId

  enum :delivery_state,
    {
      queued: "queued",
      delivered: "delivered",
      failed: "failed",
    },
    validate: true

  belongs_to :installation
  belongs_to :ingress_binding
  belongs_to :channel_connector
  belongs_to :channel_session
  belongs_to :conversation
  belongs_to :turn, optional: true
  belongs_to :message, optional: true

  validates :external_message_key, presence: true
  validate :payload_must_be_hash
  validate :failure_payload_must_be_hash
  validate :ingress_binding_installation_match
  validate :channel_connector_installation_match
  validate :channel_session_installation_match
  validate :conversation_installation_match
  validate :turn_installation_match
  validate :message_installation_match
  validate :connector_binding_match
  validate :session_binding_match
  validate :conversation_matches_channel_session
  validate :payload_public_refs
  validate :failure_payload_public_refs

  before_validation :apply_defaults
  before_validation :normalize_payloads

  private

  def apply_defaults
    self.delivery_state = "queued" if delivery_state.blank?
    self.payload = {} if payload.blank?
    self.failure_payload = {} if failure_payload.blank?
  end

  def normalize_payloads
    self.payload = payload.deep_stringify_keys if payload.is_a?(Hash)
    self.failure_payload = failure_payload.deep_stringify_keys if failure_payload.is_a?(Hash)
  end

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
  end

  def failure_payload_must_be_hash
    errors.add(:failure_payload, "must be a hash") unless failure_payload.is_a?(Hash)
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

  def conversation_installation_match
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def turn_installation_match
    return if turn.blank? || turn.installation_id == installation_id

    errors.add(:turn, "must belong to the same installation")
  end

  def message_installation_match
    return if message.blank? || message.installation_id == installation_id

    errors.add(:message, "must belong to the same installation")
  end

  def connector_binding_match
    return if channel_connector.blank? || ingress_binding.blank?
    return if channel_connector.ingress_binding_id == ingress_binding_id

    errors.add(:channel_connector, "must belong to the ingress binding")
  end

  def session_binding_match
    return if channel_session.blank? || ingress_binding.blank?
    return if channel_session.ingress_binding_id == ingress_binding_id && channel_session.channel_connector_id == channel_connector_id

    errors.add(:channel_session, "must belong to the ingress binding and channel connector")
  end

  def conversation_matches_channel_session
    return if conversation.blank? || channel_session.blank?
    return if channel_session.conversation_id == conversation_id

    errors.add(:conversation, "must match the bound channel session conversation")
  end

  def payload_public_refs
    validate_public_refs(:payload, payload)
  end

  def failure_payload_public_refs
    validate_public_refs(:failure_payload, failure_payload)
  end

  def validate_public_refs(attribute, payload_hash)
    return unless payload_hash.is_a?(Hash)

    {
      "ingress_binding_id" => ingress_binding,
      "channel_connector_id" => channel_connector,
      "channel_session_id" => channel_session,
      "conversation_id" => conversation,
      "turn_id" => turn,
      "message_id" => message,
    }.each do |key, record|
      next unless payload_hash.key?(key)
      next if record.present? && payload_hash[key] == record.public_id

      errors.add(attribute, "must use public ids for external resource references")
      break
    end
  end
end
