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
        context = Fenix::Runtime::PayloadContext.call(
          payload: @mailbox_item.fetch("payload"),
          defaults: @mailbox_item.slice("logical_work_id", "attempt_no", "runtime_plane")
        )
        Fenix::Operator::Snapshot.call(
          workspace_root: context.dig("workspace_context", "workspace_root"),
          conversation_id: context.fetch("conversation_id"),
          agent_task_run_id: context["agent_task_run_id"],
          agent_program_version_id: context.dig("runtime_identity", "agent_program_version_id")
        )

        context.merge(
          "item_id" => @mailbox_item.fetch("item_id"),
          "protocol_message_id" => @mailbox_item.fetch("protocol_message_id"),
        )
      end
    end
  end
end
