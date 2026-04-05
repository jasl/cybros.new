class AgentControlReportReceipt < ApplicationRecord
  STRUCTURED_PAYLOAD_KEYS = %w[
    attempt_no
    conversation_id
    logical_work_id
    mailbox_item_id
    method_id
    protocol_message_id
    request_kind
    runtime_plane
    turn_id
    workflow_node_id
  ].freeze

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
    (report_document&.payload || {}).deep_dup.merge(structured_payload_fields)
  end

  def payload=(value)
    @pending_payload = value
  end

  private

  def materialize_pending_payload
    return unless defined?(@pending_payload)
    return if installation.blank? || @pending_payload.blank?
    return unless @pending_payload.is_a?(Hash)

    self.report_document = JsonDocuments::Store.call(
      installation: installation,
      document_kind: "agent_control_report",
      payload: compact_payload_for_storage(@pending_payload)
    )
  end

  def payload_must_be_hash_when_provided
    return unless defined?(@pending_payload)
    return if @pending_payload.blank? || @pending_payload.is_a?(Hash)

    errors.add(:payload, "must be a hash")
  end

  def compact_payload_for_storage(payload)
    payload.deep_stringify_keys.except(*STRUCTURED_PAYLOAD_KEYS, "control")
  end

  def structured_payload_fields
    {
      "protocol_message_id" => protocol_message_id,
      "method_id" => method_id,
      "logical_work_id" => logical_work_id,
      "attempt_no" => attempt_no,
      "mailbox_item_id" => mailbox_item&.public_id,
      "runtime_plane" => mailbox_item&.runtime_plane,
      "request_kind" => mailbox_item&.payload&.fetch("request_kind", nil),
      "conversation_id" => resolved_conversation&.public_id,
      "turn_id" => resolved_turn&.public_id,
      "workflow_node_id" => resolved_workflow_node&.public_id,
    }.compact
  end

  def resolved_agent_task_run
    agent_task_run || mailbox_item&.agent_task_run
  end

  def resolved_workflow_node
    resolved_agent_task_run&.workflow_node || mailbox_item&.workflow_node
  end

  def resolved_turn
    resolved_agent_task_run&.turn || resolved_workflow_node&.turn
  end

  def resolved_conversation
    resolved_agent_task_run&.conversation || resolved_workflow_node&.conversation
  end
end
