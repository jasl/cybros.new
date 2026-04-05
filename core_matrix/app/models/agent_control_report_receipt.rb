class AgentControlReportReceipt < ApplicationRecord
  before_validation :materialize_pending_payload

  belongs_to :installation
  belongs_to :agent_session, optional: true
  belongs_to :execution_session, optional: true
  belongs_to :agent_task_run, optional: true
  belongs_to :mailbox_item, class_name: "AgentControlMailboxItem", optional: true
  belongs_to :report_document, class_name: "JsonDocument", optional: true

  validates :protocol_message_id, presence: true, uniqueness: { scope: :installation_id }
  validates :method_id, presence: true
  validates :result_code, presence: true
  validate :payload_must_be_hash_when_provided

  def payload
    report_document&.payload || {}
  end

  def payload=(value)
    @pending_payload = value
  end

  private

  def materialize_pending_payload
    return unless defined?(@pending_payload)
    return if installation.blank? || @pending_payload.blank?

    self.report_document = JsonDocuments::Store.call(
      installation: installation,
      document_kind: "agent_control_report",
      payload: @pending_payload
    )
  end

  def payload_must_be_hash_when_provided
    return unless defined?(@pending_payload)
    return if @pending_payload.blank? || @pending_payload.is_a?(Hash)

    errors.add(:payload, "must be a hash")
  end
end
