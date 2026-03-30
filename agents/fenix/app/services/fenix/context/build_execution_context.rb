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
        workspace_root = Fenix::Workspace::Layout.default_root
        Fenix::Workspace::Bootstrap.call(
          workspace_root:,
          conversation_id: payload.fetch("conversation_id")
        )
        agent_context = payload.fetch("agent_context", {})
        Fenix::Operator::Snapshot.call(
          workspace_root:,
          conversation_id: payload.fetch("conversation_id")
        )

        {
          "item_id" => @mailbox_item.fetch("item_id"),
          "protocol_message_id" => @mailbox_item.fetch("protocol_message_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no").to_i,
          "runtime_plane" => @mailbox_item.fetch("runtime_plane", "agent"),
          "agent_task_run_id" => payload.fetch("agent_task_run_id"),
          "workflow_run_id" => payload.fetch("workflow_run_id"),
          "workflow_node_id" => payload.fetch("workflow_node_id"),
          "conversation_id" => payload.fetch("conversation_id"),
          "turn_id" => payload.fetch("turn_id"),
          "kind" => payload.fetch("kind"),
          "task_payload" => payload.fetch("task_payload", {}),
          "context_messages" => payload.fetch("context_messages", []),
          "budget_hints" => payload.fetch("budget_hints", {}),
          "agent_context" => agent_context,
          "provider_execution" => payload.fetch("provider_execution", {}),
          "model_context" => payload.fetch("model_context", {}),
          "workspace_context" => {
            "workspace_root" => workspace_root,
            "env_overlay" => Fenix::Workspace::EnvOverlay.call(
              workspace_root:,
              conversation_id: payload.fetch("conversation_id")
            ),
            "prompts" => Fenix::Prompts::Assembler.call(
              workspace_root:,
              conversation_id: payload.fetch("conversation_id"),
              profile: agent_context.fetch("profile", "main"),
              is_subagent: agent_context.fetch("is_subagent", false)
            ),
          },
        }
      end
    end
  end
end
