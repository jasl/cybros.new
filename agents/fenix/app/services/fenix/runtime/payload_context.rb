module Fenix
  module Runtime
    class PayloadContext
      def self.call(...)
        new(...).call
      end

      def initialize(payload:, defaults: {})
        @payload = payload.deep_stringify_keys
        @defaults = defaults.deep_stringify_keys
      end

      def call
        Fenix::Workspace::Bootstrap.call(
          workspace_root:,
          conversation_id:,
          agent_program_version_id: runtime_identity.fetch("agent_program_version_id")
        )

        {
          "agent_task_run_id" => task["agent_task_run_id"],
          "workflow_run_id" => task["workflow_run_id"],
          "workflow_node_id" => task["workflow_node_id"],
          "conversation_id" => conversation_id,
          "turn_id" => task["turn_id"],
          "kind" => task["kind"],
          "task_payload" => @payload.fetch("task_payload", {}),
          "logical_work_id" => runtime_context["logical_work_id"].presence || @defaults["logical_work_id"],
          "attempt_no" => (runtime_context["attempt_no"].presence || @defaults["attempt_no"] || 1).to_i,
          "runtime_plane" => runtime_context["runtime_plane"].presence || @defaults["runtime_plane"] || "program",
          "context_messages" => normalized_messages,
          "context_imports" => normalized_projection_entries("context_imports"),
          "prior_tool_results" => normalized_projection_entries("prior_tool_results"),
          "budget_hints" => provider_context.fetch("budget_hints", {}).deep_stringify_keys,
          "agent_context" => normalized_agent_context,
          "capability_projection" => capability_projection,
          "provider_execution" => provider_context.fetch("provider_execution", {}).deep_stringify_keys,
          "model_context" => provider_context.fetch("model_context", {}).deep_stringify_keys,
          "runtime_identity" => runtime_identity,
          "workspace_context" => {
            "workspace_root" => workspace_root,
            "env_overlay" => Fenix::Workspace::EnvOverlay.call(
              workspace_root:,
              conversation_id:,
              agent_program_version_id: runtime_identity.fetch("agent_program_version_id")
            ),
            "prompts" => Fenix::Prompts::Assembler.call(
              workspace_root:,
              conversation_id:,
              agent_program_version_id: runtime_identity.fetch("agent_program_version_id"),
              profile: normalized_agent_context.fetch("profile", "main"),
              is_subagent: normalized_agent_context.fetch("is_subagent", false)
            ),
          },
        }.compact
      end

      private

      def task
        @task ||= @payload.fetch("task").deep_stringify_keys
      end

      def conversation_projection
        @conversation_projection ||= @payload.fetch("conversation_projection", {}).deep_stringify_keys
      end

      def capability_projection
        @capability_projection ||= @payload.fetch("capability_projection").deep_stringify_keys
      end

      def provider_context
        @provider_context ||= @payload.fetch("provider_context").deep_stringify_keys
      end

      def runtime_context
        @runtime_context ||= @payload.fetch("runtime_context", {}).deep_stringify_keys
      end

      def normalized_agent_context
        @normalized_agent_context ||= {
          "profile" => capability_projection["profile_key"] || "main",
          "is_subagent" => capability_projection["is_subagent"] == true,
          "subagent_session_id" => capability_projection["subagent_session_id"],
          "parent_subagent_session_id" => capability_projection["parent_subagent_session_id"],
          "subagent_depth" => capability_projection["subagent_depth"],
          "allowed_tool_names" => Array(capability_projection["tool_surface"]).filter_map { |entry| entry["tool_name"] },
          "owner_conversation_id" => capability_projection["owner_conversation_id"],
        }.compact
      end

      def normalized_messages
        Array(conversation_projection.fetch("messages", [])).map do |entry|
          candidate = entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : {}
          {
            "role" => candidate.fetch("role"),
            "content" => candidate.fetch("content"),
          }
        end
      end

      def normalized_projection_entries(key)
        Array(conversation_projection.fetch(key, [])).map do |entry|
          entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : {}
        end
      end

      def runtime_identity
        @runtime_identity ||= {
          "agent_program_version_id" => runtime_context.fetch("agent_program_version_id"),
        }
      end

      def workspace_root
        @workspace_root ||= Fenix::Workspace::Layout.default_root
      end

      def conversation_id
        @conversation_id ||= task.fetch("conversation_id")
      end
    end
  end
end
