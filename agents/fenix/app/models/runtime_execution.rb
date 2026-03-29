class RuntimeExecution < ApplicationRecord
  enum :status,
    {
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
    },
    validate: true

  validates :execution_id, presence: true, uniqueness: true
  validates :mailbox_item_id, presence: true
  validates :protocol_message_id, presence: true
  validates :logical_work_id, presence: true
  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validates :runtime_plane, presence: true
  validate :mailbox_item_payload_must_be_hash
  validate :reports_must_be_array
  validate :trace_must_be_array

  before_validation :assign_execution_id, on: :create

  def terminal?
    completed? || failed?
  end

  private

  def assign_execution_id
    self.execution_id ||= "execution-#{SecureRandom.uuid}"
  end

  def mailbox_item_payload_must_be_hash
    errors.add(:mailbox_item_payload, "must be a hash") unless mailbox_item_payload.is_a?(Hash)
  end

  def reports_must_be_array
    errors.add(:reports, "must be an array") unless reports.is_a?(Array)
  end

  def trace_must_be_array
    errors.add(:trace, "must be an array") unless trace.is_a?(Array)
  end
end
