class ConversationSupervisionSession < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  enum :lifecycle_state,
    {
      open: "open",
      closed: "closed",
    },
    validate: true
  enum :responder_strategy,
    {
      summary_model: "summary_model",
      builtin: "builtin",
    },
    validate: true

  data_lifecycle_kind! :ephemeral_observability

  belongs_to :installation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :initiator, polymorphic: true

  has_many :conversation_supervision_snapshots,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_supervision_session
  has_many :conversation_supervision_messages,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_supervision_session
  has_many :conversation_control_requests,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_supervision_session

  before_validation :sync_closed_at

  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :target_conversation_installation_match
  validate :target_conversation_owner_context_match
  validate :initiator_installation_match
  validate :capability_policy_snapshot_must_be_hash

  private

  def target_conversation_installation_match
    return if target_conversation.blank?
    return if target_conversation.installation_id == installation_id

    errors.add(:target_conversation, "must belong to the same installation")
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

  def initiator_installation_match
    return if initiator.blank?
    return unless initiator.respond_to?(:installation_id)
    return if initiator.installation_id == installation_id

    errors.add(:initiator, "must belong to the same installation")
  end

  def capability_policy_snapshot_must_be_hash
    errors.add(:capability_policy_snapshot, "must be a hash") unless capability_policy_snapshot.is_a?(Hash)
  end

  def sync_closed_at
    if closed?
      self.closed_at ||= Time.current
    else
      self.closed_at = nil
    end
  end
end
