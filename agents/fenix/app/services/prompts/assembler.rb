require "json"

module Prompts
  class Assembler
    def self.call(...)
      new(...).call
    end

    def initialize(profile:, is_subagent:, global_instructions:, skill_overlay:, durable_state:, execution_context:, routing_summary: nil, catalog: nil)
      @profile = profile.to_s
      @is_subagent = is_subagent == true
      @global_instructions = global_instructions
      @skill_overlay = Array(skill_overlay).filter_map(&:presence)
      @durable_state = durable_state.presence
      @execution_context = execution_context.presence || {}
      @routing_summary = routing_summary.presence
      @catalog = catalog || ProfileCatalogLoader.default
    end

    def call
      {
        "system_prompt" => [
          section("Code-Owned Base", bundle.soul_prompt),
          section("Role Overlay", role_overlay),
          routing_section,
          section("Global Instructions", global_instruction_text),
          section("Skill Overlay", skill_overlay_text),
          section("Supervisor Guidance", supervisor_guidance_text),
          section("CoreMatrix Durable State", durable_state_text),
          section("Execution-Local Fenix Context", execution_context_text),
        ].compact.join("\n\n"),
      }
    end

    private

    def section(title, body)
      "## #{title}\n#{body.to_s.strip}"
    end

    def role_overlay
      bundle.prompt_for(mode: @is_subagent ? :subagent : :interactive)
    end

    def routing_section
      return nil unless @routing_summary

      section("Specialist Routing", @routing_summary)
    end

    def global_instruction_text
      @global_instructions.presence || "No global instructions provided."
    end

    def skill_overlay_text
      return "No active skills loaded." if @skill_overlay.empty?

      @skill_overlay.join("\n\n")
    end

    def durable_state_text
      return "No durable state view provided by CoreMatrix." unless @durable_state.present?

      JSON.pretty_generate(@durable_state)
    end

    def supervisor_guidance_text
      guidance = @durable_state&.dig("supervisor_guidance")
      return "No active supervisor guidance." unless guidance.is_a?(Hash)

      latest_guidance = guidance["latest_guidance"]
      return "No active supervisor guidance." unless latest_guidance.is_a?(Hash)

      lines = [
        "Latest guidance (#{guidance["guidance_scope"] || "unknown"}): #{latest_guidance["content"].presence || "No guidance content provided."}",
      ]

      recent_guidance = Array(guidance["recent_guidance"])
      if recent_guidance.any?
        lines << "Recent guidance history:"
        recent_guidance.each do |entry|
          candidate = entry.is_a?(Hash) ? entry : {}
          delivered_at = candidate["delivered_at"].presence || "unknown-time"
          content = candidate["content"].presence || "No guidance content provided."
          lines << "- [#{delivered_at}] #{content}"
        end
      end

      lines.join("\n")
    end

    def execution_context_text
      return "No execution-local context provided." if @execution_context.blank?

      JSON.pretty_generate(@execution_context)
    end

    def bundle
      @bundle ||= @catalog.resolve(profile_key: @profile, is_subagent: @is_subagent)
    end
  end
end
