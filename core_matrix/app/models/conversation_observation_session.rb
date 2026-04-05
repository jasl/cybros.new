class ConversationObservationSession < ApplicationRecord
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
      builtin: "builtin",
      program_contract: "program_contract",
    },
    validate: true

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :initiator, polymorphic: true

  has_many :conversation_observation_frames,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_observation_session
  has_many :conversation_observation_messages,
    dependent: :restrict_with_exception,
    inverse_of: :conversation_observation_session

  validate :target_conversation_installation_match
  validate :initiator_installation_match
  validate :capability_policy_snapshot_must_be_hash

  data_lifecycle_kind! :ephemeral_observability

  private

  def target_conversation_installation_match
    return if target_conversation.blank?
    return if target_conversation.installation_id == installation_id

    errors.add(:target_conversation, "must belong to the same installation")
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
end
