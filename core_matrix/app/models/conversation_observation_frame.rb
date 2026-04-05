class ConversationObservationFrame < ApplicationRecord
  include HasPublicId

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :conversation_observation_session

  has_many :conversation_observation_messages,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_observation_frame

  validates :anchor_turn_sequence_snapshot, numericality: { only_integer: true }, allow_nil: true
  validates :conversation_event_projection_sequence_snapshot, numericality: { only_integer: true }, allow_nil: true
  validate :target_conversation_match
  validate :session_installation_match
  validate :snapshot_payloads_must_be_hashes_or_arrays

  private

  def target_conversation_match
    return if conversation_observation_session.blank? || target_conversation.blank?
    return if conversation_observation_session.target_conversation_id == target_conversation_id

    errors.add(:target_conversation, "must match the observation session target conversation")
  end

  def session_installation_match
    return if conversation_observation_session.blank? || installation.blank?
    return if conversation_observation_session.installation_id == installation_id

    errors.add(:conversation_observation_session, "must belong to the same installation")
  end

  def snapshot_payloads_must_be_hashes_or_arrays
    errors.add(:active_subagent_session_public_ids, "must be an array") unless active_subagent_session_public_ids.is_a?(Array)
    errors.add(:bundle_snapshot, "must be a hash") unless bundle_snapshot.is_a?(Hash)
    errors.add(:assessment_payload, "must be a hash") unless assessment_payload.is_a?(Hash)
  end
end
