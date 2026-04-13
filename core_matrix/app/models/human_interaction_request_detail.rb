class HumanInteractionRequestDetail < ApplicationRecord
  belongs_to :human_interaction_request, inverse_of: :human_interaction_request_detail

  validate :request_payload_must_be_hash
  validate :result_payload_must_be_hash

  private

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def result_payload_must_be_hash
    errors.add(:result_payload, "must be a hash") unless result_payload.is_a?(Hash)
  end
end
