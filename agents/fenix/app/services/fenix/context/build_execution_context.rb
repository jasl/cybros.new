module Fenix
  module Context
    class BuildExecutionContext
      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:)
        @mailbox_item = mailbox_item.deep_stringify_keys
      end

      def call
        payload = @mailbox_item.fetch("payload")

        {
          "item_id" => @mailbox_item.fetch("item_id"),
          "message_id" => @mailbox_item.fetch("message_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no").to_i,
          "agent_task_run_id" => payload.fetch("agent_task_run_id"),
          "workflow_run_id" => payload.fetch("workflow_run_id"),
          "workflow_node_id" => payload.fetch("workflow_node_id"),
          "conversation_id" => payload.fetch("conversation_id"),
          "turn_id" => payload.fetch("turn_id"),
          "task_kind" => payload.fetch("task_kind"),
          "task_payload" => payload.fetch("task_payload", {}),
          "context_messages" => payload.fetch("context_messages", []),
          "budget_hints" => payload.fetch("budget_hints", {}),
          "provider_execution" => payload.fetch("provider_execution", {}),
          "model_context" => payload.fetch("model_context", {}),
        }
      end
    end
  end
end
