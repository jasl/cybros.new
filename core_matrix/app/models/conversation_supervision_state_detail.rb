class ConversationSupervisionStateDetail < ApplicationRecord
  belongs_to :conversation_supervision_state, inverse_of: :conversation_supervision_state_detail

  validate :status_payload_must_be_hash

  private

  def status_payload_must_be_hash
    errors.add(:status_payload, "must be a hash") unless status_payload.is_a?(Hash)
  end
end
