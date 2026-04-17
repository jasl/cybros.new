module AgentControl
  class SerializeMailboxItem
    EVENT_SUBMISSION_PATH = "/execution_runtime_api/events/batch".freeze
    ATTACHMENT_REFRESH_PATH = "/execution_runtime_api/attachments/request".freeze
    ATTACHMENT_PUBLISH_PATH = "/execution_runtime_api/attachments/publish".freeze

    def self.call(mailbox_item, execution_snapshot_cache: nil)
      {
        "item_id" => mailbox_item.public_id,
        "item_type" => mailbox_item.item_type,
        "control_plane" => mailbox_item.control_plane,
        "logical_work_id" => mailbox_item.logical_work_id,
        "attempt_no" => mailbox_item.attempt_no,
        "delivery_no" => mailbox_item.delivery_no,
        "protocol_message_id" => mailbox_item.protocol_message_id,
        "causation_id" => mailbox_item.causation_id,
        "priority" => mailbox_item.priority,
        "status" => mailbox_item.status,
        "available_at" => mailbox_item.available_at&.iso8601,
        "dispatch_deadline_at" => mailbox_item.dispatch_deadline_at&.iso8601,
        "lease_timeout_seconds" => mailbox_item.lease_timeout_seconds,
        "execution_hard_deadline_at" => mailbox_item.execution_hard_deadline_at&.iso8601,
        "payload" => serialized_payload(mailbox_item, execution_snapshot_cache:),
      }.compact
    end

    def self.serialized_payload(mailbox_item, compact_payload: nil, execution_snapshot: nil, execution_snapshot_cache: nil)
      execution_snapshot ||= execution_snapshot_for(mailbox_item, execution_snapshot_cache)
      return mailbox_item.materialized_payload(execution_snapshot:) if mailbox_item.payload_document.present?

      compact_payload ||= mailbox_item.payload_body
      return compact_payload unless mailbox_item.execution_assignment? && mailbox_item.execution_contract.present?

      snapshot = execution_snapshot || mailbox_item.execution_contract.turn.execution_snapshot
      payload = compact_payload.deep_stringify_keys

      {
        "protocol_version" => "agent-runtime/2026-04-01",
        "request_kind" => "execution_assignment",
        "task" => {
          "agent_task_run_id" => mailbox_item.agent_task_run&.public_id,
          "workflow_run_id" => mailbox_item.agent_task_run&.workflow_run&.public_id,
          "workflow_node_id" => mailbox_item.agent_task_run&.workflow_node&.public_id,
          "conversation_id" => mailbox_item.agent_task_run&.conversation&.public_id,
          "turn_id" => mailbox_item.agent_task_run&.turn&.public_id,
          "kind" => mailbox_item.agent_task_run&.kind,
        }.compact,
        "conversation_projection" => snapshot.conversation_projection.merge(
          "prior_tool_results" => Array(payload["prior_tool_results"]).map { |entry| entry.deep_stringify_keys }
        ),
        "capability_projection" => snapshot.capability_projection,
        "provider_context" => snapshot.provider_context,
        "transport_hints" => transport_hints,
        "runtime_context" => snapshot.runtime_context.merge(
          "control_plane" => mailbox_item.control_plane,
          "logical_work_id" => mailbox_item.logical_work_id,
          "attempt_no" => mailbox_item.attempt_no,
          "agent_definition_version_id" => mailbox_item.execution_contract.agent_definition_version.public_id,
          "event_submission_path" => EVENT_SUBMISSION_PATH,
          "attachment_refresh_path" => ATTACHMENT_REFRESH_PATH,
          "attachment_publish_path" => ATTACHMENT_PUBLISH_PATH
        ),
        "task_payload" => payload["task_payload"] || mailbox_item.agent_task_run&.task_payload || {},
      }.merge(payload.except("task_payload", "prior_tool_results"))
    end

    def self.execution_snapshot_for(mailbox_item, execution_snapshot_cache)
      return if execution_snapshot_cache.blank?

      turn_id =
        if mailbox_item.execution_assignment?
          mailbox_item.agent_task_run&.turn_id
        elsif mailbox_item.agent_request?
          mailbox_item.execution_contract&.turn_id
        end

      execution_snapshot_cache[turn_id] if turn_id.present?
    end

    def self.transport_hints
      ExecutionRuntimeSessions::Open.send(:transport_hints).deep_dup
    end
  end
end
