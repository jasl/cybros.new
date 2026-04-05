class ConversationCapabilityPolicy < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  data_lifecycle_kind! :owner_bound

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"

  validates :target_conversation, uniqueness: true
  validate :target_conversation_installation_match
  validate :policy_payload_must_be_hash

  private

  def target_conversation_installation_match
    return if target_conversation.blank?
    return if target_conversation.installation_id == installation_id

    errors.add(:target_conversation, "must belong to the same installation")
  end

  def policy_payload_must_be_hash
    errors.add(:policy_payload, "must be a hash") unless policy_payload.is_a?(Hash)
  end
end
