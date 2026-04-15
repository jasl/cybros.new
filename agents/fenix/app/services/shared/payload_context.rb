module Shared
  class PayloadContext
    def self.call(...)
      new(...).call
    end

    def initialize(payload:, defaults: {})
      @payload = payload.deep_stringify_keys
      @defaults = defaults.deep_stringify_keys
    end

    def call
      {
        "task" => task,
        "conversation_id" => conversation_id,
        "workflow_node_id" => task["workflow_node_id"],
        "turn_id" => task["turn_id"],
        "kind" => task["kind"],
        "agent_context" => agent_context,
        "provider_context" => provider_context,
        "runtime_context" => runtime_context,
        "workspace_agent_context" => workspace_agent_context,
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

    def conversation_id
      task.fetch("conversation_id")
    end

    def round_context
      @round_context ||= @payload.fetch("round_context", {}).deep_stringify_keys
    end

    def agent_context
      projected = @payload.fetch("agent_context", {}).deep_stringify_keys

      {
        "profile" => projected["profile"] || "main",
        "is_subagent" => projected["is_subagent"] == true,
        "subagent_connection_id" => projected["subagent_connection_id"],
        "parent_subagent_connection_id" => projected["parent_subagent_connection_id"],
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

    def workspace_agent_context
      normalize_context_payload(@payload["workspace_agent_context"])
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
      explicit = normalize_context_payload(@payload["memory_context"])
      return explicit if explicit.present?
      return @defaults.fetch("memory_context", {}) if @defaults.key?("memory_context")
      {}
    end

    def skill_context
      explicit = normalize_context_payload(@payload["skill_context"])
      return explicit if explicit.present?
      return @defaults.fetch("skill_context", {}) if @defaults.key?("skill_context")
      empty_skill_context
    end

    def empty_skill_context
      {
        "active_skill_names" => [],
        "active_skill_contents" => [],
      }
    end

    def normalize_context_payload(value)
      return {} if value.blank?

      value.respond_to?(:deep_stringify_keys) ? value.deep_stringify_keys : value
    end
  end
end
