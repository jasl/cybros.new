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
    payload = (report_document&.payload || {}).deep_dup
    reconstructed_response = reconstructed_response_payload(payload)
    if reconstructed_response.present?
      existing_response = payload["response_payload"].is_a?(Hash) ? payload["response_payload"].deep_dup : {}
      payload["response_payload"] = existing_response.merge(reconstructed_response)
    end
    payload.merge(structured_payload_fields)
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
    compact = payload.deep_stringify_keys.except(*STRUCTURED_PAYLOAD_KEYS, "control")
    response_payload = compact["response_payload"]
    return compact unless compact_program_tool_report_response?(response_payload)

    compact_response = compact_response_payload(response_payload)
    if compact_response.present?
      compact["response_payload"] = compact_response
    else
      compact.delete("response_payload")
    end
    compact
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

  def resolved_tool_invocation
    tool_invocation_id = mailbox_item&.payload&.dig("runtime_resource_refs", "tool_invocation", "tool_invocation_id")
    return if tool_invocation_id.blank?

    resolved_agent_task_run&.tool_invocations&.find_by(public_id: tool_invocation_id) ||
      resolved_workflow_node&.tool_invocations&.find_by(public_id: tool_invocation_id) ||
      ToolInvocation.find_by(installation_id: installation_id, public_id: tool_invocation_id)
  end

  def compact_program_tool_report_response?(response_payload)
    method_id == "agent_program_completed" &&
      mailbox_item&.payload&.fetch("request_kind", nil) == "execute_program_tool" &&
      response_payload.is_a?(Hash) &&
      resolved_tool_invocation.present?
  end

  def compact_response_payload(response_payload)
    response_payload
      .deep_stringify_keys
      .except("program_tool_call")
      .tap do |compact|
        compact.delete("status") if compact["status"] == "ok"
        compact.delete("output_chunks") if Array(compact["output_chunks"]).empty?
        compact.delete("summary_artifacts") if Array(compact["summary_artifacts"]).empty?
      end
      .presence
  end

  def reconstructed_response_payload(payload)
    return {} unless method_id == "agent_program_completed"
    return {} unless mailbox_item&.payload&.fetch("request_kind", nil) == "execute_program_tool"

    existing = payload["response_payload"].is_a?(Hash) ? payload["response_payload"] : {}
    response = {}

    response["status"] = "ok" unless existing.key?("status")
    response["output_chunks"] = [] unless existing.key?("output_chunks")
    response["summary_artifacts"] = [] unless existing.key?("summary_artifacts")
    response["program_tool_call"] = mailbox_item.payload.fetch("program_tool_call") unless existing.key?("program_tool_call")

    if !existing.key?("result") && (tool_invocation = resolved_tool_invocation).present?
      response["result"] = tool_invocation.response_payload
    end

    response.compact
  end
end
