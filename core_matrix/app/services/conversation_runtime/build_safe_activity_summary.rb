module ConversationRuntime
  class BuildSafeActivitySummary
    DIRECTORY_INSPECTION_PATTERN = /
      \b(ls|pwd|find|tree)\b
    /x.freeze

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
        "phase" => phase,
        "work_type" => work_type,
        "path_summary" => workspace_path,
        "user_visible" => true,
      }.compact
    end

    private

    def summary
      label = activity_label
      location = workspace_path.present? ? " in #{workspace_path}" : nil

      case @activity_kind
      when "process"
        "#{process_verb} #{label}#{location}"
      else
        "#{command_verb} #{label}#{location}"
      end
    end

    def detail
      case @activity_kind
      when "process"
        @lifecycle_state == "running" ? "Process is still running." : "Process lifecycle changed."
      else
        case @lifecycle_state
        when "running", "waiting"
          "Command is still running."
        when "failed"
          "Command failed."
        else
          "Command completed successfully."
        end
      end
    end

    def phase
      case work_type
      when "verification", "preview", "build"
        "validate"
      when "editing"
        "build"
      else
        "plan"
      end
    end

    def work_type
      return "verification" if test_and_build_command?
      return "verification" if test_command?
      return "build" if build_command?
      return "preview" if preview_command?
      return "editing" if file_write_command?
      return "inspection" if directory_inspection_command?

      "command"
    end

    def activity_label
      case work_type
      when "verification"
        test_and_build_command? ? "the test-and-build check" : "the test run"
      when "build"
        "the production build"
      when "preview"
        "the preview server"
      when "editing"
        "game files"
      when "inspection"
        "the workspace"
      else
        "a shell command"
      end
    end

    def command_verb
      case work_type
      when "preview"
        @lifecycle_state == "running" ? "Starting" : "Started"
      when "editing"
        "Edited"
      when "inspection"
        "Inspected"
      else
        @lifecycle_state == "running" ? "Running" : "Ran"
      end
    end

    def process_verb
      @lifecycle_state == "running" ? "Starting" : "Started"
    end

    def workspace_path
      @workspace_path ||= begin
        match = @command_line.match(/\bcd\s+([^\s&;]+)\b/)
        match && match[1]
      end
    end

    def test_and_build_command?
      @command_line.include?("npm test") && @command_line.include?("npm run build")
    end

    def test_command?
      @command_line.include?("npm test") && !@command_line.include?("npm run build")
    end

    def build_command?
      @command_line.include?("npm run build") && !@command_line.include?("npm test")
    end

    def preview_command?
      @command_line.include?("npm run preview")
    end

    def file_write_command?
      @command_line.include?("cat <<") || @command_line.match?(/\s>\s*[^&|]+/)
    end

    def directory_inspection_command?
      @command_line.match?(DIRECTORY_INSPECTION_PATTERN)
    end
  end
end
