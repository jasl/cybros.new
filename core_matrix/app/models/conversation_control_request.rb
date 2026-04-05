class ConversationControlRequest < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  LIFECYCLE_STATES = %w[queued dispatched acknowledged completed failed rejected].freeze

  data_lifecycle_kind! :bounded_audit

  belongs_to :installation
  belongs_to :conversation_supervision_session
  belongs_to :target_conversation, class_name: "Conversation"

  validates :request_kind, :target_kind, presence: true
  validates :lifecycle_state, inclusion: { in: LIFECYCLE_STATES }
  validate :target_conversation_match
  validate :session_installation_match
  validate :request_payload_must_be_hash
  validate :result_payload_must_be_hash

  private

  def target_conversation_match
    return if conversation_supervision_session.blank? || target_conversation.blank?
    return if conversation_supervision_session.target_conversation_id == target_conversation_id

    errors.add(:target_conversation, "must match the supervision session target conversation")
  end

  def session_installation_match
    return if conversation_supervision_session.blank? || installation.blank?
    return if conversation_supervision_session.installation_id == installation_id

    errors.add(:conversation_supervision_session, "must belong to the same installation")
  end

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def result_payload_must_be_hash
    errors.add(:result_payload, "must be a hash") unless result_payload.is_a?(Hash)
  end
end
