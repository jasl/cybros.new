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
          "messages" => compacted.fetch("messages"),
          "program_tools" => Fenix::Runtime::PairingManifest.visible_program_tool_catalog(
            allowed_tool_names: Array(round_context.dig("agent_context", "allowed_tool_names"))
          ),
          "likely_model" => prepared.fetch("likely_model"),
          "trace" => [prepared.fetch("trace"), compacted.fetch("trace")],
        }
      end

      private

      def round_context
        @round_context ||= begin
          workspace_root = Fenix::Workspace::Layout.default_root
          conversation_id = @payload.fetch("conversation_id")
          agent_context = @payload.fetch("agent_context", {}).deep_stringify_keys
          runtime_identity = @payload.fetch("runtime_identity", {}).deep_stringify_keys

          Fenix::Workspace::Bootstrap.call(
            workspace_root:,
            conversation_id:,
            deployment_public_id: runtime_identity["deployment_public_id"]
          )

          {
            "conversation_id" => conversation_id,
            "turn_id" => @payload.fetch("turn_id"),
            "workflow_run_id" => @payload.fetch("workflow_run_id"),
            "workflow_node_id" => @payload.fetch("workflow_node_id"),
            "context_messages" => transcript_messages,
            "context_imports" => Array(@payload.fetch("context_imports", [])).map(&:deep_stringify_keys),
            "prior_tool_results" => Array(@payload.fetch("prior_tool_results", [])).map(&:deep_stringify_keys),
            "budget_hints" => @payload.fetch("budget_hints", {}).deep_stringify_keys,
            "agent_context" => agent_context,
            "provider_execution" => @payload.fetch("provider_execution", {}).deep_stringify_keys,
            "model_context" => @payload.fetch("model_context", {}).deep_stringify_keys,
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
        Array(@payload.fetch("transcript", [])).map do |entry|
          candidate = entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : {}
          {
            "role" => candidate.fetch("role"),
            "content" => candidate.fetch("content"),
          }
        end
      end
    end
  end
end
