class ChannelInboundMessage < ApplicationRecord
  include HasPublicId

  belongs_to :installation
  belongs_to :ingress_binding
  belongs_to :channel_connector
  belongs_to :channel_session
  belongs_to :conversation, optional: true

  validates :external_event_key, presence: true, uniqueness: { scope: :channel_connector_id }
  validates :external_message_key, presence: true
  validates :external_sender_id, presence: true
  validates :received_at, presence: true
  validate :sender_snapshot_must_be_hash
  validate :content_must_be_hash
  validate :normalized_payload_must_be_hash
  validate :raw_payload_must_be_hash
  validate :ingress_binding_installation_match
  validate :channel_connector_installation_match
  validate :channel_session_installation_match
  validate :conversation_installation_match
  validate :connector_binding_match
  validate :session_binding_match
  validate :conversation_matches_channel_session
  validate :normalized_payload_public_refs

  before_validation :apply_defaults
  before_validation :normalize_payloads

  private

  def apply_defaults
    self.sender_snapshot = {} if sender_snapshot.blank?
    self.content = {} if content.blank?
    self.normalized_payload = {} if normalized_payload.blank?
    self.raw_payload = {} if raw_payload.blank?
  end

  def normalize_payloads
    self.sender_snapshot = sender_snapshot.deep_stringify_keys if sender_snapshot.is_a?(Hash)
    self.content = content.deep_stringify_keys if content.is_a?(Hash)
    self.normalized_payload = normalized_payload.deep_stringify_keys if normalized_payload.is_a?(Hash)
    self.raw_payload = raw_payload.deep_stringify_keys if raw_payload.is_a?(Hash)
  end

  def sender_snapshot_must_be_hash
    errors.add(:sender_snapshot, "must be a hash") unless sender_snapshot.is_a?(Hash)
  end

  def content_must_be_hash
    errors.add(:content, "must be a hash") unless content.is_a?(Hash)
  end

  def normalized_payload_must_be_hash
    errors.add(:normalized_payload, "must be a hash") unless normalized_payload.is_a?(Hash)
  end

  def raw_payload_must_be_hash
    errors.add(:raw_payload, "must be a hash") unless raw_payload.is_a?(Hash)
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

  def normalized_payload_public_refs
    validate_public_refs(:normalized_payload, normalized_payload)
  end

  def validate_public_refs(attribute, payload)
    return unless payload.is_a?(Hash)

    {
      "ingress_binding_id" => ingress_binding,
      "channel_connector_id" => channel_connector,
      "channel_session_id" => channel_session,
      "conversation_id" => conversation,
    }.each do |key, record|
      next unless payload.key?(key)
      next if record.present? && payload[key] == record.public_id

      errors.add(attribute, "must use public ids for external resource references")
      break
    end
  end
end
