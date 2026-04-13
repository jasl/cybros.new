class ConversationDetail < ApplicationRecord
  belongs_to :conversation, inverse_of: :conversation_detail

  validate :override_payload_must_be_hash
  validate :override_reconciliation_report_must_be_hash

  private

  def override_payload_must_be_hash
    errors.add(:override_payload, "must be a hash") unless override_payload.is_a?(Hash)
  end

  def override_reconciliation_report_must_be_hash
    errors.add(:override_reconciliation_report, "must be a hash") unless override_reconciliation_report.is_a?(Hash)
  end
end
