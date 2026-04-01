require "json"

module Fenix
  module Runtime
    class PrepareRound
      def self.call(...)
        new(...).call
      end

      def initialize(payload:)
        @payload = payload.deep_stringify_keys
      end

      def call
        prepared = Fenix::Hooks::PrepareTurn.call(context: round_context)
        compacted = Fenix::Hooks::CompactContext.call(
          messages: prepared.fetch("messages"),
          budget_hints: round_context.fetch("budget_hints"),
          likely_model: prepared.fetch("likely_model")
        )

        {
          "status" => "ok",
          "messages" => compacted.fetch("messages"),
          "tool_surface" => Fenix::Runtime::PairingManifest.visible_program_tool_catalog(
            allowed_tool_names: Array(round_context.dig("agent_context", "allowed_tool_names"))
          ),
          "likely_model" => prepared.fetch("likely_model"),
          "summary_artifacts" => [],
          "trace" => [prepared.fetch("trace"), compacted.fetch("trace")],
        }
      end

      private

      def round_context
        @round_context ||= begin
          workspace_root = Fenix::Workspace::Layout.default_root
          task = @payload.fetch("task").deep_stringify_keys
          conversation_projection = @payload.fetch("conversation_projection").deep_stringify_keys
          capability_projection = @payload.fetch("capability_projection").deep_stringify_keys
          provider_context = @payload.fetch("provider_context").deep_stringify_keys
          runtime_context = @payload.fetch("runtime_context").deep_stringify_keys
          conversation_id = task.fetch("conversation_id")
          agent_context = normalized_agent_context(capability_projection:)
          runtime_identity = { "deployment_public_id" => runtime_context.fetch("deployment_public_id") }

          Fenix::Workspace::Bootstrap.call(
            workspace_root:,
            conversation_id:,
            deployment_public_id: runtime_identity["deployment_public_id"]
          )

          {
            "conversation_id" => conversation_id,
            "turn_id" => task["turn_id"],
            "workflow_run_id" => task["workflow_run_id"],
            "workflow_node_id" => task["workflow_node_id"],
            "context_messages" => transcript_messages,
            "context_imports" => Array(conversation_projection.fetch("context_imports", [])).map(&:deep_stringify_keys),
            "prior_tool_results" => Array(conversation_projection.fetch("prior_tool_results", [])).map(&:deep_stringify_keys),
            "budget_hints" => provider_context.fetch("budget_hints", {}).deep_stringify_keys,
            "agent_context" => agent_context,
            "capability_projection" => capability_projection,
            "provider_execution" => provider_context.fetch("provider_execution", {}).deep_stringify_keys,
            "model_context" => provider_context.fetch("model_context", {}).deep_stringify_keys,
            "runtime_identity" => runtime_identity,
            "workspace_context" => {
              "workspace_root" => workspace_root,
              "env_overlay" => Fenix::Workspace::EnvOverlay.call(
                workspace_root:,
                conversation_id:,
                deployment_public_id: runtime_identity["deployment_public_id"]
              ),
              "prompts" => Fenix::Prompts::Assembler.call(
                workspace_root:,
                conversation_id:,
                deployment_public_id: runtime_identity["deployment_public_id"],
                profile: agent_context.fetch("profile", "main"),
                is_subagent: agent_context.fetch("is_subagent", false)
              ),
            },
          }
        end
      end

      def transcript_messages
        source_messages = @payload.fetch("conversation_projection").deep_stringify_keys.fetch("messages")

        Array(source_messages).map do |entry|
          candidate = entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : {}
          {
            "role" => candidate.fetch("role"),
            "content" => candidate.fetch("content"),
          }
        end
      end

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
