module Fenix
  module Runtime
    class PayloadContext
      def self.call(...)
        new(...).call
      end

      def initialize(payload:, defaults: {}, memory_store: nil, skills_catalog: nil)
        @payload = payload.deep_stringify_keys
        @defaults = defaults.deep_stringify_keys
        @memory_store = memory_store
        @skills_catalog = skills_catalog
      end

      def call
        {
          "task" => task,
          "conversation_id" => task["conversation_id"],
          "workflow_node_id" => task["workflow_node_id"],
          "turn_id" => task["turn_id"],
          "kind" => task["kind"],
          "agent_context" => agent_context,
          "provider_context" => provider_context,
          "runtime_context" => runtime_context,
          "workspace_context" => workspace_context,
          "transcript_messages" => transcript_messages,
          "context_imports" => context_imports,
          "work_context_view" => work_context_view,
          "memory_context" => memory_context,
          "skill_context" => skill_context,
        }.compact
      end

      private

      def task
        @task ||= @payload.fetch("task").deep_stringify_keys
      end

      def round_context
        @round_context ||= @payload.fetch("round_context", {}).deep_stringify_keys
      end

      def agent_context
        projected = @payload.fetch("agent_context", {}).deep_stringify_keys

        {
          "profile" => projected["profile"] || "main",
          "is_subagent" => projected["is_subagent"] == true,
          "subagent_session_id" => projected["subagent_session_id"],
          "parent_subagent_session_id" => projected["parent_subagent_session_id"],
          "subagent_depth" => projected["subagent_depth"],
          "owner_conversation_id" => projected["owner_conversation_id"],
          "allowed_tool_names" => Array(projected["allowed_tool_names"]).map(&:to_s),
        }.compact
      end

      def provider_context
        @payload.fetch("provider_context", {}).deep_stringify_keys
      end

      def runtime_context
        @payload.fetch("runtime_context", {}).deep_stringify_keys
      end

      def workspace_context
        explicit = @payload.fetch("workspace_context", {}).deep_stringify_keys
        workspace_root = explicit["workspace_root"].presence ||
          @defaults["workspace_root"].presence ||
          ENV["FENIX_WORKSPACE_ROOT"].presence ||
          Dir.pwd

        explicit.merge("workspace_root" => Pathname.new(workspace_root).expand_path.to_s)
      end

      def transcript_messages
        Array(round_context["messages"]).map do |entry|
          candidate = entry.deep_stringify_keys
          {
            "role" => candidate.fetch("role"),
            "content" => candidate.fetch("content"),
          }
        end
      end

      def context_imports
        Array(round_context["context_imports"]).map { |entry| entry.deep_stringify_keys }
      end

      def work_context_view
        value = round_context["work_context_view"]
        value.respond_to?(:deep_stringify_keys) ? value.deep_stringify_keys : value
      end

      def memory_context
        return @defaults.fetch("memory_context", {}) if @defaults.key?("memory_context")

        memory_store.summary_payload
      end

      def skill_context
        return @defaults.fetch("skill_context", {}) if @defaults.key?("skill_context")

        selected_skills = skills_catalog.active_for_messages(messages: transcript_messages)

        {
          "active_skill_names" => selected_skills.map { |entry| entry.fetch("name") },
          "active_skill_contents" => selected_skills.map { |entry| entry.fetch("skill_md") },
        }
      end

      def memory_store
        @memory_store ||= Fenix::Memory::Store.new(
          workspace_root: workspace_context.fetch("workspace_root"),
          conversation_id: task.fetch("conversation_id")
        )
      end

      def skills_catalog
        @skills_catalog ||= Fenix::Skills::Catalog.new
      end
    end
  end
end
