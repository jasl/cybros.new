class ConversationSupervisionMessage < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  enum :role,
    {
      user: "user",
      supervisor_agent: "supervisor_agent",
      system: "system",
    },
    validate: true

  data_lifecycle_kind! :ephemeral_observability

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :conversation_supervision_session
  belongs_to :conversation_supervision_snapshot

  validates :content, presence: true
  validate :target_conversation_match
  validate :session_installation_match
  validate :snapshot_installation_match
  validate :snapshot_session_match

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

  def snapshot_installation_match
    return if conversation_supervision_snapshot.blank? || installation.blank?
    return if conversation_supervision_snapshot.installation_id == installation_id

    errors.add(:conversation_supervision_snapshot, "must belong to the same installation")
  end

  def snapshot_session_match
    return if conversation_supervision_snapshot.blank? || conversation_supervision_session.blank?
    return if conversation_supervision_snapshot.conversation_supervision_session_id == conversation_supervision_session_id

    errors.add(:conversation_supervision_snapshot, "must belong to the same supervision session")
  end
end
