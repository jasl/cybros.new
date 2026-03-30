class RuntimeExecution < ApplicationRecord
  enum :status,
    {
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true

  validates :execution_id, presence: true, uniqueness: true
  validates :agent_task_run_id, presence: true, on: :create
  validates :mailbox_item_id, presence: true
  validates :protocol_message_id, presence: true
  validates :logical_work_id, presence: true
  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validates :runtime_plane, presence: true
  validate :mailbox_item_payload_must_be_hash
  validate :reports_must_be_array
  validate :trace_must_be_array

  before_validation :assign_execution_id, on: :create
  before_validation :assign_agent_task_run_id, on: :create

  scope :active_for_agent_task, ->(agent_task_run_id) { where(agent_task_run_id:, status: %w[queued running]) }

  def terminal?
    completed? || failed? || canceled?
  end

  def cancel!(request_kind: nil, reason_kind: nil, occurred_at: Time.current)
    return self if terminal?

    error_payload = {
      "failure_kind" => "canceled",
      "last_error_summary" => "execution canceled by agent task close request",
    }
    error_payload["close_request_kind"] = request_kind if request_kind.present?
    error_payload["reason_kind"] = reason_kind if reason_kind.present?

    update!(
      status: "canceled",
      finished_at: occurred_at,
      error_payload:
    )
  end

  private

  def assign_execution_id
    self.execution_id ||= "execution-#{SecureRandom.uuid}"
  end

  def assign_agent_task_run_id
    self.agent_task_run_id ||= mailbox_item_payload.dig("payload", "agent_task_run_id")
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
