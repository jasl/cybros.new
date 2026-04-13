class WorkflowRunWaitDetail < ApplicationRecord
  belongs_to :workflow_run, inverse_of: :workflow_run_wait_detail

  validate :wait_reason_payload_must_be_hash

  private

  def wait_reason_payload_must_be_hash
    errors.add(:wait_reason_payload, "must be a hash") unless wait_reason_payload.is_a?(Hash)
  end
end
