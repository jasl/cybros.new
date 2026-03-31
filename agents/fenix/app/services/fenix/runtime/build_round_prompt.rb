require "json"

module Fenix
  module Runtime
    class BuildRoundPrompt
      def self.call(...)
        new(...).call
      end

      def initialize(prompts:, context_imports:, skill_selection:)
        @prompts = prompts.deep_stringify_keys
        @context_imports = Array(context_imports).map(&:deep_stringify_keys)
        @skill_selection = skill_selection.deep_stringify_keys
      end

      def call
        sections = []
        append_text_section(sections, "Agent Prompt", @prompts["agent_prompt"])
        append_text_section(sections, "Soul", @prompts["soul"])
        append_text_section(sections, "User", @prompts["user"])
        append_text_section(sections, "Memory", @prompts["memory"])
        append_text_section(sections, "Conversation Summary", @prompts["conversation_summary"])
        append_text_section(sections, "Operator Prompt", @prompts["operator_prompt"])
        append_json_section(sections, "Operator State", @prompts["operator_state"])
        append_active_skills_section(sections)
        append_selected_skills_section(sections)
        append_context_imports_section(sections)
        sections.join("\n\n")
      end

      private

      def append_text_section(sections, heading, body)
        return if body.blank?

        sections << "#{heading}:\n#{body.to_s.strip}"
      end

      def append_json_section(sections, heading, payload)
        return if payload.blank?

        sections << "#{heading}:\n#{JSON.pretty_generate(payload)}"
      end

      def append_active_skills_section(sections)
        active_catalog = @skill_selection.fetch("active_catalog", [])
        return if active_catalog.blank?

        lines = active_catalog.map do |entry|
          "- #{entry.fetch("name")}: #{entry.fetch("description")}"
        end

        sections << "Active Skills:\n#{lines.join("\n")}"
      end

      def append_selected_skills_section(sections)
        selected_skills = @skill_selection.fetch("selected_skills", [])
        return if selected_skills.blank?

        selected_sections = selected_skills.map do |skill|
          "Skill #{skill.fetch("name")}:\n#{skill.fetch("skill_md").to_s.strip}"
        end

        sections << "Selected Skills:\n#{selected_sections.join("\n\n")}"
      end

      def append_context_imports_section(sections)
        return if @context_imports.blank?

        imports = @context_imports.map { |entry| JSON.pretty_generate(entry) }
        sections << "Context Imports:\n#{imports.join("\n\n")}"
      end
    end
  end
end
