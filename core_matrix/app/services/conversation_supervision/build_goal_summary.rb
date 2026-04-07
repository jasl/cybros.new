module ConversationSupervision
  class BuildGoalSummary
    ACTION_LINE_PATTERN = /\A(?:build|implement|create|fix|update|add|refactor|write|review|investigate|complete|develop|ship|make|support|ensure)\b/i.freeze
    META_LINE_PATTERNS = [
      /`\$[a-z0-9-]+`/i,
      /\b(?:using-superpowers|find-skills)\b/i,
      /\binstalled and available\b/i,
      /\bno screenshots\b/i,
      /\bvisual design review\b/i,
      /\bproceed autonomously\b/i,
      /\bask(?:ing)? more questions\b/i,
      /\Ayour previous attempt did not satisfy the acceptance harness\.?\z/i,
      /\Athis is repair attempt\b/i,
      /\Aobserved problems:?\z/i,
      /\Adesign is approved\.?\z/i,
      /\Arequirements:?\z/i,
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(content:)
      @content = content.to_s
    end

    def call
      summary = actionable_lines.find { |line| line.match?(ACTION_LINE_PATTERN) } || actionable_lines.first
      return if summary.blank?

      normalized = summary.gsub(/`([^`]+)`/, "\\1")
      normalized = normalize_repair_summary(normalized)
      normalized = "#{normalized}." unless normalized.end_with?(".")
      normalized.truncate(SupervisionStateFields::HUMAN_SUMMARY_MAX_LENGTH)
    end

    private

    def normalize_repair_summary(summary)
      match = summary.match(/\AContinue working in\s+(\S+)\s+and fix the existing app\b/i)
      return "Fix the existing app in #{match[1]}" if match.present?

      summary
    end

    def actionable_lines
      @actionable_lines ||= @content.lines.filter_map do |line|
        stripped = line.to_s.squish
        next if stripped.blank?
        next if stripped.start_with?("-", "*")
        next if META_LINE_PATTERNS.any? { |pattern| stripped.match?(pattern) }

        stripped
      end
    end
  end
end
