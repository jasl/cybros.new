class AgentTaskRunDetail < ApplicationRecord
  belongs_to :agent_task_run, inverse_of: :agent_task_run_detail

  validate :task_payload_must_be_hash
  validate :progress_payload_must_be_hash
  validate :supervision_payload_must_be_hash
  validate :terminal_payload_must_be_hash
  validate :close_outcome_payload_must_be_hash

  private

  def task_payload_must_be_hash
    errors.add(:task_payload, "must be a hash") unless task_payload.is_a?(Hash)
  end

  def progress_payload_must_be_hash
    errors.add(:progress_payload, "must be a hash") unless progress_payload.is_a?(Hash)
  end

  def supervision_payload_must_be_hash
    errors.add(:supervision_payload, "must be a hash") unless supervision_payload.is_a?(Hash)
  end

  def terminal_payload_must_be_hash
    errors.add(:terminal_payload, "must be a hash") unless terminal_payload.is_a?(Hash)
  end

  def close_outcome_payload_must_be_hash
    errors.add(:close_outcome_payload, "must be a hash") unless close_outcome_payload.is_a?(Hash)
  end
end
