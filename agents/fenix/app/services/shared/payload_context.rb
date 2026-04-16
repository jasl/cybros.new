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
      explicit = normalize_context_payload(@payload["workspace_agent_context"])
      return {} if explicit.blank?

      {
        "workspace_agent_id" => explicit["workspace_agent_id"],
        "global_instructions" => explicit["global_instructions"],
        "profile_settings" => normalize_profile_settings(explicit["profile_settings"]),
      }.compact
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

    def normalize_profile_settings(value)
      explicit = normalize_context_payload(value)
      return {} if explicit.blank?

      normalized = {}
      normalized["interactive_profile_key"] = explicit["interactive_profile_key"].to_s if explicit["interactive_profile_key"].present?
      normalized["interactive_model_selector"] = explicit["interactive_model_selector"].to_s if explicit["interactive_model_selector"].present?
      normalized["default_subagent_profile_key"] = explicit["default_subagent_profile_key"].to_s if explicit["default_subagent_profile_key"].present?

      enabled_keys = Array(explicit["enabled_subagent_profile_keys"]).map(&:to_s).filter_map(&:presence).uniq
      normalized["enabled_subagent_profile_keys"] = enabled_keys if enabled_keys.any?

      normalized["delegation_mode"] = explicit["delegation_mode"].to_s if explicit["delegation_mode"].present?
      normalized["max_concurrent_subagents"] = explicit["max_concurrent_subagents"].to_i if explicit["max_concurrent_subagents"].present?
      normalized["max_subagent_depth"] = explicit["max_subagent_depth"].to_i if explicit["max_subagent_depth"].present?
      default_subagent_model_selector =
        explicit["default_subagent_model_selector"].presence ||
          explicit["default_subagent_model_selector_hint"].presence
      if default_subagent_model_selector.present?
        normalized["default_subagent_model_selector"] = default_subagent_model_selector.to_s
        normalized["default_subagent_model_selector_hint"] = default_subagent_model_selector.to_s
      end

      subagent_model_selectors = normalize_context_payload(explicit["subagent_model_selectors"])
      if subagent_model_selectors.is_a?(Hash)
        normalized_selectors = subagent_model_selectors.each_with_object({}) do |(profile_key, selector), out|
          normalized_selector = selector.to_s.strip
          next if normalized_selector.blank?

          out[profile_key.to_s] = normalized_selector
        end
        normalized["subagent_model_selectors"] = normalized_selectors if normalized_selectors.any?
      end

      if explicit.key?("allow_nested_subagents")
        normalized["allow_nested_subagents"] = explicit["allow_nested_subagents"] == true
      end

      normalized
    end
  end
end
