class BuildRoundInstructions
  def self.call(...)
    new(...).call
  end

  def initialize(context:, catalog: Prompts::ProfileCatalogLoader.default)
    @context = context.deep_stringify_keys
    @catalog = catalog
  end

  def call
    assembled_prompt = Prompts::Assembler.call(
      profile: selected_profile_key,
      is_subagent: @context.dig("agent_context", "is_subagent") == true,
      global_instructions: global_instructions,
      skill_overlay: skill_overlay,
      durable_state: @context["work_context_view"],
      execution_context: execution_context,
      routing_summary: routing_summary
    )

    {
      "messages" => [
        { "role" => "system", "content" => assembled_prompt.fetch("system_prompt") },
        *Array(@context["transcript_messages"]),
      ],
      "visible_tool_names" => Array(@context.dig("agent_context", "allowed_tool_names")).map(&:to_s),
    }
  end

  private

  def global_instructions
    @context.dig("workspace_agent_context", "global_instructions")
  end

  def skill_overlay
    Array(@context.dig("skill_context", "active_skill_contents"))
  end

  def execution_context
    {
      "memory" => @context.dig("memory_context", "summary") || "No conversation memory loaded.",
      "runtime" => @context.fetch("runtime_context", {}),
      "provider" => @context.fetch("provider_context", {}),
    }
  end

  def routing_summary
    Prompts::RoutingSummary.call(
      settings_payload: @context.dig("workspace_agent_context", "settings_payload") || {}
    )
  end

  def selected_profile_key
    explicit_profile = @context.dig("agent_context", "profile_key").presence
    return explicit_profile if explicit_profile.present?

    @context.dig("workspace_agent_context", "settings_payload", "agent", "interactive", "profile_key").presence || @catalog.default_interactive_key
  end
end
