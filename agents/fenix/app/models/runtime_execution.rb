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
  validates :mailbox_item_id, presence: true
  validates :protocol_message_id, presence: true
  validates :logical_work_id, presence: true
  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validates :runtime_plane, presence: true
  validates :item_type, presence: true
  validates :request_kind, presence: true
  validate :request_payload_must_be_hash
  validate :reports_must_be_array
  validate :trace_must_be_array

  before_validation :assign_execution_id, on: :create
  before_validation :assign_item_type, on: :create
  before_validation :assign_request_kind, on: :create
  before_validation :assign_agent_task_run_id, on: :create

  scope :active_for_agent_task, ->(agent_task_run_id) { where(agent_task_run_id:, status: %w[queued running]) }

  def terminal?
    completed? || failed? || canceled?
  end

  def dispatchable?
    queued? && started_at.blank? && finished_at.blank? && enqueued_at.blank?
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

  def to_mailbox_item
    {
      "item_id" => mailbox_item_id,
      "item_type" => item_type,
      "protocol_message_id" => protocol_message_id,
      "logical_work_id" => logical_work_id,
      "attempt_no" => attempt_no,
      "runtime_plane" => runtime_plane,
      "payload" => request_payload.deep_stringify_keys,
    }
  end

  private

  def assign_execution_id
    self.execution_id ||= "execution-#{SecureRandom.uuid}"
  end

  def assign_item_type
    self.item_type = item_type.presence || "execution_assignment"
  end

  def assign_request_kind
    self.request_kind = request_kind.presence || request_payload.deep_stringify_keys["request_kind"].presence || item_type
  end

  def assign_agent_task_run_id
    self.agent_task_run_id ||= request_payload.deep_stringify_keys.dig("task", "agent_task_run_id")
  end

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def reports_must_be_array
    errors.add(:reports, "must be an array") unless reports.is_a?(Array)
  end

  def trace_must_be_array
    errors.add(:trace, "must be an array") unless trace.is_a?(Array)
  end
end
