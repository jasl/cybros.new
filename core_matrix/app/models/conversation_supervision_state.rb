class ConversationSupervisionState < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  OVERALL_STATES = %w[queued running waiting blocked completed failed interrupted canceled].freeze

  data_lifecycle_kind! :recomputable

  belongs_to :installation
  belongs_to :target_conversation, class_name: "Conversation"

  validates :overall_state, inclusion: { in: OVERALL_STATES }
  validates :target_conversation, uniqueness: true
  validate :target_conversation_installation_match
  validate :status_payload_must_be_hash

  private

  def target_conversation_installation_match
    return if target_conversation.blank?
    return if target_conversation.installation_id == installation_id

    errors.add(:target_conversation, "must belong to the same installation")
  end

  def status_payload_must_be_hash
    errors.add(:status_payload, "must be a hash") unless status_payload.is_a?(Hash)
  end
end
