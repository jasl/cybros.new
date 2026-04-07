module ConversationRuntime
  class BuildSafeActivitySummary
    def self.call(...)
      new(...).call
    end

    def initialize(activity_kind:, command_line:, lifecycle_state:)
      @activity_kind = activity_kind.to_s
      @command_line = command_line.to_s
      @lifecycle_state = lifecycle_state.to_s
    end

    def call
      {
        "summary" => summary,
        "detail" => detail,
        "phase" => "runtime",
        "work_type" => @activity_kind,
        "path_summary" => workspace_path,
        "user_visible" => true,
      }.compact
    end

    private

    def summary
      [subject_phrase, location_phrase].compact.join
    end

    def detail
      case lifecycle_bucket
      when :active
        "#{subject_noun.capitalize} is still running."
      when :failed
        "#{subject_noun.capitalize} failed."
      when :interrupted
        "#{subject_noun.capitalize} was interrupted."
      else
        "#{subject_noun.capitalize} finished."
      end
    end

    def subject_phrase
      case lifecycle_bucket
      when :active
        "#{article}#{subject_noun} is running"
      when :failed
        "#{article}#{subject_noun} failed"
      when :interrupted
        "#{article}#{subject_noun} was interrupted"
      else
        "#{article}#{subject_noun} finished"
      end
    end

    def location_phrase
      return if workspace_path.blank?

      " in #{workspace_path}"
    end

    def subject_noun
      @activity_kind == "process" ? "process" : "shell command"
    end

    def article
      "A "
    end

    def lifecycle_bucket
      return :active if %w[starting running waiting].include?(@lifecycle_state)
      return :failed if @lifecycle_state == "failed"
      return :interrupted if %w[canceled interrupted lost stopped].include?(@lifecycle_state)

      :completed
    end

    def workspace_path
      @workspace_path ||= begin
        match = @command_line.match(/\bcd\s+([^\s&;]+)\b/)
        match && match[1]
      end
    end
  end
end
