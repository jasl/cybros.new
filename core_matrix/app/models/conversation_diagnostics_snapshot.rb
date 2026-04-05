class ConversationDiagnosticsSnapshot < ApplicationRecord
  include DataLifecycle

  belongs_to :installation
  belongs_to :conversation
  belongs_to :most_expensive_turn, class_name: "Turn", optional: true
  belongs_to :most_rounds_turn, class_name: "Turn", optional: true

  validates :lifecycle_state, presence: true
  validate :metadata_must_be_hash
  validate :installation_matches_conversation
  validate :outlier_turns_belong_to_conversation

  data_lifecycle_kind! :recomputable

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def installation_matches_conversation
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def outlier_turns_belong_to_conversation
    [most_expensive_turn, most_rounds_turn].compact.each do |turn|
      next if turn.conversation_id == conversation_id

      errors.add(:base, "outlier turns must belong to the same conversation")
      break
    end
  end
end
