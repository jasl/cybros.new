class ConversationSupervisionSnapshot < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  data_lifecycle_kind! :ephemeral_observability

  belongs_to :installation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :conversation_supervision_session

  has_many :conversation_supervision_messages,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_supervision_snapshot

  validates :anchor_turn_sequence_snapshot, numericality: { only_integer: true }, allow_nil: true
  validates :conversation_event_projection_sequence_snapshot, numericality: { only_integer: true }, allow_nil: true
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :target_conversation_match
  validate :target_conversation_owner_context_match
  validate :session_installation_match
  validate :snapshot_payloads_must_be_hashes_or_arrays

  private

  def target_conversation_match
    return if conversation_supervision_session.blank? || target_conversation.blank?
    return if conversation_supervision_session.target_conversation_id == target_conversation_id

    errors.add(:target_conversation, "must match the supervision session target conversation")
  end

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def target_conversation_owner_context_match
    return if target_conversation.blank?

    errors.add(:user, "must match the target conversation user") if user.present? && target_conversation.user_id != user_id
    errors.add(:workspace, "must match the target conversation workspace") if workspace.present? && target_conversation.workspace_id != workspace_id
    errors.add(:agent, "must match the target conversation agent") if agent.present? && target_conversation.agent_id != agent_id
  end

  def session_installation_match
    return if conversation_supervision_session.blank? || installation.blank?
    return if conversation_supervision_session.installation_id == installation_id

    errors.add(:conversation_supervision_session, "must belong to the same installation")
  end

  def snapshot_payloads_must_be_hashes_or_arrays
    errors.add(:active_subagent_connection_public_ids, "must be an array") unless active_subagent_connection_public_ids.is_a?(Array)
    errors.add(:bundle_payload, "must be a hash") unless bundle_payload.is_a?(Hash)
    errors.add(:machine_status_payload, "must be a hash") unless machine_status_payload.is_a?(Hash)
  end
end
