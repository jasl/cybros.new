class ConversationObservationMessage < ApplicationRecord
  include HasPublicId

  enum :role,
    {
      user: "user",
      observer_agent: "observer_agent",
      system: "system",
    },
    validate: true

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :conversation_observation_session
  belongs_to :conversation_observation_frame

  validates :content, presence: true
  validate :metadata_must_be_hash
  validate :target_conversation_match
  validate :session_installation_match
  validate :frame_installation_match
  validate :frame_session_match

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

  def frame_installation_match
    return if conversation_observation_frame.blank? || installation.blank?
    return if conversation_observation_frame.installation_id == installation_id

    errors.add(:conversation_observation_frame, "must belong to the same installation")
  end

  def frame_session_match
    return if conversation_observation_frame.blank? || conversation_observation_session.blank?
    return if conversation_observation_frame.conversation_observation_session_id == conversation_observation_session_id

    errors.add(:conversation_observation_frame, "must belong to the same observation session")
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end
end
