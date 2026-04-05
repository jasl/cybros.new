class TurnDiagnosticsSnapshot < ApplicationRecord
  include DataLifecycle

  belongs_to :installation
  belongs_to :conversation
  belongs_to :turn

  validates :lifecycle_state, presence: true
  validate :metadata_must_be_hash
  validate :installation_matches_conversation
  validate :installation_matches_turn
  validate :turn_matches_conversation

  data_lifecycle_kind! :recomputable

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def installation_matches_conversation
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def installation_matches_turn
    return if turn.blank? || turn.installation_id == installation_id

    errors.add(:turn, "must belong to the same installation")
  end

  def turn_matches_conversation
    return if turn.blank? || conversation.blank?
    return if turn.conversation_id == conversation_id

    errors.add(:turn, "must belong to the same conversation")
  end
end
