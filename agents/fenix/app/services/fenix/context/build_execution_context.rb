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
        payload = @mailbox_item.fetch("payload").deep_stringify_keys
        task = payload.fetch("task").deep_stringify_keys
        conversation_projection = payload.fetch("conversation_projection").deep_stringify_keys
        capability_projection = payload.fetch("capability_projection").deep_stringify_keys
        provider_context = payload.fetch("provider_context").deep_stringify_keys
        runtime_context = payload.fetch("runtime_context").deep_stringify_keys
        runtime_identity = { "deployment_public_id" => runtime_context.fetch("deployment_public_id") }
        workspace_root = Fenix::Workspace::Layout.default_root
        Fenix::Workspace::Bootstrap.call(
          workspace_root:,
          conversation_id: task.fetch("conversation_id"),
          deployment_public_id: runtime_identity["deployment_public_id"]
        )
        agent_context = normalized_agent_context(capability_projection:)
        Fenix::Operator::Snapshot.call(
          workspace_root:,
          conversation_id: task.fetch("conversation_id"),
          agent_task_run_id: task["agent_task_run_id"],
          deployment_public_id: runtime_identity["deployment_public_id"]
        )

        {
          "item_id" => @mailbox_item.fetch("item_id"),
          "protocol_message_id" => @mailbox_item.fetch("protocol_message_id"),
          "logical_work_id" => runtime_context["logical_work_id"].presence || @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => runtime_context["attempt_no"].presence&.to_i || @mailbox_item.fetch("attempt_no").to_i,
          "runtime_plane" => runtime_context["runtime_plane"].presence || @mailbox_item.fetch("runtime_plane", "agent"),
          "agent_task_run_id" => task["agent_task_run_id"],
          "workflow_run_id" => task["workflow_run_id"],
          "workflow_node_id" => task["workflow_node_id"],
          "conversation_id" => task.fetch("conversation_id"),
          "turn_id" => task["turn_id"],
          "kind" => task["kind"],
          "task_payload" => payload.fetch("task_payload", {}),
          "context_messages" => conversation_projection.fetch("messages"),
          "budget_hints" => provider_context.fetch("budget_hints", {}),
          "agent_context" => agent_context,
          "capability_projection" => capability_projection,
          "provider_execution" => provider_context.fetch("provider_execution", {}),
          "model_context" => provider_context.fetch("model_context", {}),
          "runtime_identity" => runtime_identity,
          "workspace_context" => {
            "workspace_root" => workspace_root,
            "env_overlay" => Fenix::Workspace::EnvOverlay.call(
              workspace_root:,
              conversation_id: task.fetch("conversation_id"),
              deployment_public_id: runtime_identity["deployment_public_id"]
            ),
            "prompts" => Fenix::Prompts::Assembler.call(
              workspace_root:,
              conversation_id: task.fetch("conversation_id"),
              deployment_public_id: runtime_identity["deployment_public_id"],
              profile: agent_context.fetch("profile", "main"),
              is_subagent: agent_context.fetch("is_subagent", false)
            ),
          },
        }
      end

      private

      def normalized_agent_context(capability_projection:)
        {
          "profile" => capability_projection["profile_key"] || "main",
          "is_subagent" => capability_projection["is_subagent"] == true,
          "subagent_session_id" => capability_projection["subagent_session_id"],
          "parent_subagent_session_id" => capability_projection["parent_subagent_session_id"],
          "subagent_depth" => capability_projection["subagent_depth"],
          "allowed_tool_names" => Array(capability_projection["tool_surface"]).filter_map { |entry| entry["tool_name"] },
          "owner_conversation_id" => capability_projection["owner_conversation_id"],
        }.compact
      end
    end
  end
end
