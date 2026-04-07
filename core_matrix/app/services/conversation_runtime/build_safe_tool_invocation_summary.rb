module ConversationRuntime
  class BuildSafeToolInvocationSummary
    def self.call(...)
      new(...).call
    end

    def initialize(tool_name:, arguments: {}, response_payload: {}, command_summary: nil, command_metadata: {})
      @tool_name = tool_name.to_s
      @arguments = arguments.to_h.deep_stringify_keys
      @response_payload = response_payload.to_h.deep_stringify_keys
      @command_summary = command_summary.to_s.strip
      @command_metadata = command_metadata.to_h.deep_stringify_keys
    end

    def call
      case @tool_name
      when "workspace_tree"
        workspace_summary(
          title: "Inspect the workspace tree",
          summary: "Inspected the workspace tree",
          started_summary: "Started inspecting the workspace tree."
        )
      when "workspace_read"
        workspace_summary(
          title: "Review workspace files",
          summary: "Reviewed workspace files",
          started_summary: "Started reviewing workspace files."
        )
      when "workspace_find"
        {
          "title" => "Search workspace files",
          "summary" => "Searched workspace files",
          "started_summary" => "Started searching workspace files.",
          "detail" => workspace_search_detail,
          "phase" => "plan",
          "user_visible" => true,
        }
      when "workspace_stat"
        workspace_summary(
          title: "Inspect workspace metadata",
          summary: "Inspected workspace metadata",
          started_summary: "Started inspecting workspace metadata."
        )
      when "workspace_write", "workspace_patch"
        workspace_summary(
          title: "Edit workspace files",
          summary: "Edited workspace files",
          started_summary: "Started editing workspace files."
        )
      when "subagent_spawn"
        profile_key = @response_payload["profile_key"].presence || @arguments["profile_key"].presence || "worker"
        {
          "title" => "Delegate child work",
          "summary" => "Spawned child task #{profile_key}#1",
          "started_summary" => "Started delegating child work.",
          "detail" => "Delegated with profile `#{profile_key}`.",
          "phase" => "build",
          "user_visible" => true,
        }
      when "subagent_send"
        subagent_summary(
          title: "Message a child task",
          summary: "Messaged a child task",
          started_summary: "Started messaging a child task."
        )
      when "subagent_wait"
        subagent_summary(
          title: "Wait for a child task",
          summary: "Waited for a child task",
          started_summary: "Started waiting for a child task."
        )
      when "subagent_list"
        subagent_summary(
          title: "Review child task status",
          summary: "Reviewed child task status",
          started_summary: "Started reviewing child task status."
        )
      when "subagent_close"
        subagent_summary(
          title: "Close a child task",
          summary: "Closed a child task",
          started_summary: "Started closing a child task."
        )
      when "write_stdin"
        write_stdin_summary
      when "command_run_wait"
        command_run_wait_summary
      when "command_run_read_output"
        command_wrapper_summary(
          title: "Review output from",
          summary: "Reviewed output from",
          started_summary: "Started reviewing output from",
          detail: "Read the latest output from"
        )
      when "command_run_terminate"
        command_wrapper_summary(
          title: "Stop",
          summary: "Stopped",
          started_summary: "Started stopping",
          detail: "Stopped"
        )
      when "command_run_list"
        {
          "title" => "Review shell command status",
          "summary" => "Reviewed shell command status",
          "started_summary" => "Started reviewing shell command status.",
          "detail" => "Checked the state of running shell commands.",
          "phase" => "validate",
          "user_visible" => true,
        }
      when "browser_open"
        browser_summary(
          title_prefix: "Open the browser",
          summary_prefix: "Opened the browser",
          started_prefix: "Started opening the browser",
          detail: "Opened a browser session for verification."
        )
      when "browser_list"
        browser_summary(
          title_prefix: "Review browser sessions",
          summary_prefix: "Reviewed browser sessions",
          started_prefix: "Started reviewing browser sessions",
          detail: "Checked the available browser sessions."
        )
      when "browser_session_info"
        browser_summary(
          title_prefix: "Inspect the browser session",
          summary_prefix: "Inspected the browser session",
          started_prefix: "Started inspecting the browser session",
          detail: "Checked the current browser session details."
        )
      when "browser_navigate"
        browser_summary(
          title_prefix: "Navigate the browser",
          summary_prefix: "Navigated the browser",
          started_prefix: "Started navigating the browser",
          detail: "Moved the browser session to a new page."
        )
      when "browser_get_content"
        {
          "title" => "Capture browser content",
          "summary" => "Captured browser content",
          "started_summary" => "Started capturing browser content.",
          "detail" => "Read the browser output for verification.",
          "phase" => "validate",
          "user_visible" => true,
        }
      when "browser_screenshot"
        browser_summary(
          title_prefix: "Capture a browser screenshot",
          summary_prefix: "Captured a browser screenshot",
          started_prefix: "Started capturing a browser screenshot",
          detail: "Captured a browser screenshot for verification."
        )
      when "browser_close"
        browser_summary(
          title_prefix: "Close the browser session",
          summary_prefix: "Closed the browser session",
          started_prefix: "Started closing the browser session",
          detail: "Closed the browser session."
        )
      when /\Aworkspace_/
        workspace_summary(
          title: "Review workspace state",
          summary: "Reviewed workspace state",
          started_summary: "Started reviewing workspace state."
        )
      when /\Acommand_run_/
        {
          "title" => "Review shell command state",
          "summary" => "Reviewed shell command state",
          "started_summary" => "Started reviewing shell command state.",
          "detail" => "Checked the state of shell command execution.",
          "phase" => "validate",
          "user_visible" => true,
        }
      when /\Abrowser_/
        browser_summary(
          title_prefix: "Review browser state",
          summary_prefix: "Reviewed browser state",
          started_prefix: "Started reviewing browser state",
          detail: "Checked browser state for verification."
        )
      end
    end

    private

    def workspace_summary(title:, summary:, started_summary:)
      {
        "title" => title,
        "summary" => summary,
        "started_summary" => started_summary,
        "detail" => "Path `#{workspace_path}`.",
        "phase" => "plan",
        "user_visible" => true,
      }
    end

    def subagent_summary(title:, summary:, started_summary:)
      {
        "title" => title,
        "summary" => summary,
        "started_summary" => started_summary,
        "detail" => "Coordinated with delegated child work.",
        "phase" => "build",
        "user_visible" => true,
      }
    end

    def command_wrapper_summary(title:, summary:, started_summary:, detail:)
      target = command_target

      {
        "title" => "#{title} #{target}",
        "summary" => "#{summary} #{target}",
        "started_summary" => "#{started_summary} #{target}.",
        "detail" => "#{detail} #{target}.",
        "phase" => "validate",
        "user_visible" => true,
      }
    end

    def write_stdin_summary
      return completed_command_summary if command_session_closed? && command_metadata_present?

      target = command_progress_target

      {
        "title" => "Check progress on #{target}",
        "summary" => "Checked progress on #{target}",
        "started_summary" => "Started checking progress on #{target}.",
        "detail" => "Checked the latest progress for #{target}.",
        "phase" => command_phase,
        "user_visible" => true,
      }
    end

    def command_run_wait_summary
      return inspection_wait_summary if inspection_command?
      target = command_progress_target

      {
        "title" => "Wait for #{target}",
        "summary" => "Waiting for #{target}",
        "started_summary" => "Started waiting for #{target}.",
        "detail" => "Continuing to wait for #{target}.",
        "phase" => command_phase,
        "user_visible" => true,
      }
    end

    def inspection_wait_summary
      title = command_location.present? ? "Inspect the workspace in #{command_location}" : "Inspect the workspace"
      summary = command_location.present? ? "Inspecting the workspace in #{command_location}" : "Inspecting the workspace"

      {
        "title" => title,
        "summary" => summary,
        "started_summary" => "Started #{lowercase_initial(summary)}.",
        "detail" => "Inspecting workspace contents.",
        "phase" => command_phase,
        "user_visible" => true,
      }
    end

    def completed_command_summary
      summary = command_summary_text

      {
        "title" => summary,
        "summary" => summary,
        "started_summary" => sentence(started_summary_for(summary)),
        "detail" => "Collected the final result from #{command_progress_target}.",
        "phase" => command_phase,
        "user_visible" => true,
      }
    end

    def browser_summary(title_prefix:, summary_prefix:, started_prefix:, detail:)
      target = browser_target

      {
        "title" => join_target(title_prefix, target),
        "summary" => join_target(summary_prefix, target),
        "started_summary" => "#{join_target(started_prefix, target)}.",
        "detail" => detail,
        "phase" => "validate",
        "user_visible" => true,
      }
    end

    def browser_target
      @arguments["url"].presence ||
        @response_payload["current_url"].presence
    end

    def command_phase
      @command_metadata["phase"].presence || "build"
    end

    def command_metadata_present?
      @command_metadata.present?
    end

    def command_session_closed?
      @response_payload["session_closed"] == true
    end

    def inspection_command?
      command_work_type == "inspection"
    end

    def command_work_type
      @command_metadata["work_type"].presence
    end

    def command_location
      @command_metadata["path_summary"].presence
    end

    def command_summary_text
      @command_metadata["summary"].presence || @command_summary.presence || "The command completed"
    end

    def command_progress_target
      case command_work_type
      when "verification"
        verification_target
      when "build"
        located_target("the production build")
      when "app_server"
        located_target("the app server")
      when "preview"
        located_target("the preview server")
      when "scaffolding"
        located_target("the React app scaffold")
      when "dependency_setup"
        located_target("project dependency installation")
      when "editing"
        located_target("game file updates")
      when "inspection"
        located_target("workspace inspection")
      else
        command_target
      end
    end

    def verification_target
      summary = command_summary_text
      prefix = summary.match?(/test-and-build check/i) ? "the test-and-build check" : "the test run"
      located_target(prefix)
    end

    def command_target
      @command_summary.presence || "the running command"
    end

    def located_target(prefix)
      return prefix if command_location.blank?

      "#{prefix} in #{command_location}"
    end

    def join_target(prefix, target)
      return prefix if target.blank?

      "#{prefix} at #{target}"
    end

    def started_summary_for(summary)
      normalized = summary.to_s
      return normalized.sub(/\AStarting\b/i, "Started") if normalized.match?(/\AStarting\b/i)
      return normalized.sub(/\ARunning\b/i, "Started") if normalized.match?(/\ARunning\b/i)
      return normalized.sub(/\AInspecting\b/i, "Started inspecting") if normalized.match?(/\AInspecting\b/i)
      return normalized.sub(/\AInspected\b/i, "Started inspecting") if normalized.match?(/\AInspected\b/i)
      return normalized.sub(/\AInstalling\b/i, "Started installing") if normalized.match?(/\AInstalling\b/i)
      return normalized.sub(/\AInstalled\b/i, "Started installing") if normalized.match?(/\AInstalled\b/i)
      return normalized.sub(/\AScaffolding\b/i, "Started scaffolding") if normalized.match?(/\AScaffolding\b/i)
      return normalized.sub(/\AScaffolded\b/i, "Started scaffolding") if normalized.match?(/\AScaffolded\b/i)
      return normalized.sub(/\AEditing\b/i, "Started editing") if normalized.match?(/\AEditing\b/i)
      return normalized.sub(/\AEdited\b/i, "Started editing") if normalized.match?(/\AEdited\b/i)
      return normalized.sub(/\ARan\b/i, "Started") if normalized.match?(/\ARan\b/i)

      normalized
    end

    def lowercase_initial(text)
      return text if text.blank?

      text[0].downcase + text[1..]
    end

    def sentence(text)
      return text if text.blank? || text.end_with?(".")

      "#{text}."
    end

    def workspace_search_detail
      segments = []
      segments << "Query `#{@arguments["query"]}`" if @arguments["query"].present?
      segments << "path `#{workspace_path}`"

      "#{segments.join(" in ")}."
    end

    def workspace_path
      @arguments["path"].presence || @arguments["file_path"].presence || "/workspace"
    end
  end
end
