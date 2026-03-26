module AgentControl
  class SerializeMailboxItem
    def self.call(mailbox_item)
      {
        "item_id" => mailbox_item.public_id,
        "item_type" => mailbox_item.item_type,
        "target_kind" => mailbox_item.target_kind,
        "target_ref" => mailbox_item.target_ref,
        "logical_work_id" => mailbox_item.logical_work_id,
        "attempt_no" => mailbox_item.attempt_no,
        "delivery_no" => mailbox_item.delivery_no,
        "message_id" => mailbox_item.message_id,
        "causation_id" => mailbox_item.causation_id,
        "priority" => mailbox_item.priority,
        "status" => mailbox_item.status,
        "available_at" => mailbox_item.available_at&.iso8601,
        "dispatch_deadline_at" => mailbox_item.dispatch_deadline_at&.iso8601,
        "lease_timeout_seconds" => mailbox_item.lease_timeout_seconds,
        "execution_hard_deadline_at" => mailbox_item.execution_hard_deadline_at&.iso8601,
        "payload" => mailbox_item.payload,
      }.compact
    end
  end
end
