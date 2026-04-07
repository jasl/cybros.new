module ConversationRuntime
  class BuildSafeActivitySummary
    DEV_SERVER_PATTERN = /
      \b(?:npm|pnpm|yarn|bun)\s+run\s+dev\b|
      \bvite\b.*\b--host\b
    /x.freeze
    SCAFFOLD_PATTERN = /
      \b(?:npm|pnpm|yarn|bun)\s+create\s+vite(?:@latest)?\b
    /x.freeze
    DEPENDENCY_INSTALL_PATTERN = /
      \b(?:npm|pnpm|yarn|bun)\s+install\b
    /x.freeze
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
      when "verification", "preview", "app_server", "build"
        "validate"
      when "editing", "dependency_setup", "scaffolding"
        "build"
      else
        "plan"
      end
    end

    def work_type
      return "verification" if test_and_build_command?
      return "verification" if test_command?
      return "build" if build_command?
      return "app_server" if app_server_command?
      return "preview" if preview_command?
      return "scaffolding" if scaffold_command?
      return "dependency_setup" if dependency_install_command?
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
      when "app_server"
        "the app server"
      when "preview"
        "the preview server"
      when "scaffolding"
        "the React app"
      when "dependency_setup"
        "project dependencies"
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
      when "app_server"
        @lifecycle_state == "running" ? "Starting" : "Started"
      when "preview"
        @lifecycle_state == "running" ? "Starting" : "Started"
      when "scaffolding"
        @lifecycle_state == "running" ? "Scaffolding" : "Scaffolded"
      when "dependency_setup"
        @lifecycle_state == "running" ? "Installing" : "Installed"
      when "editing"
        @lifecycle_state == "running" ? "Editing" : "Edited"
      when "inspection"
        @lifecycle_state == "running" ? "Inspecting" : "Inspected"
      else
        @lifecycle_state == "running" ? "Running" : "Ran"
      end
    end

    def process_verb
      @lifecycle_state == "running" ? "Starting" : "Started"
    end

    def workspace_path
      @workspace_path ||= begin
        scaffold_target_path || begin
          match = @command_line.match(/\bcd\s+([^\s&;]+)\b/)
          match && match[1]
        end
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

    def app_server_command?
      @command_line.match?(DEV_SERVER_PATTERN)
    end

    def scaffold_command?
      @command_line.match?(SCAFFOLD_PATTERN)
    end

    def dependency_install_command?
      @command_line.match?(DEPENDENCY_INSTALL_PATTERN) && !@command_line.include?("npm install -g")
    end

    def file_write_command?
      @command_line.include?("cat <<") || @command_line.match?(/\s>\s*[^&|]+/)
    end

    def directory_inspection_command?
      @command_line.match?(DIRECTORY_INSPECTION_PATTERN)
    end

    def scaffold_target_path
      return unless scaffold_command?

      base_match = @command_line.match(/\bcd\s+([^\s&;]+)\b/)
      target_match = @command_line.match(/\bcreate\s+vite(?:@latest)?\s+([^\s&;]+)\b/)
      base_path = base_match && base_match[1]
      target = target_match && target_match[1]

      return target if target.present? && target.start_with?("/")
      return if base_path.blank? || target.blank?

      File.join(base_path, target)
    end
  end
end
