module ConversationSupervision
  class BuildRuntimeFocusHint
    ACTIVE_COMMAND_STATES = %w[starting running].freeze
    ACTIVE_PROCESS_STATES = %w[starting running].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, workflow_run: nil)
      @conversation = conversation
      @workflow_run = workflow_run
    end

    def call
      active_command_hint ||
        active_process_hint ||
        latest_command_hint ||
        latest_process_hint
    end

    private

    def active_command_hint
      command_run = active_command_run
      return if command_run.blank?

      build_command_hint(
        command_run: command_run,
        kind: "command_wait",
        fragment_prefix: "waiting for",
        sentence_prefix: "Waiting for",
        waiting: true,
        recent_progress_summary: latest_completed_command_summary || started_summary_for(command_run_summary(command_run))
      )
    end

    def active_process_hint
      process_run = active_process_run
      return if process_run.blank?

      build_process_hint(
        process_run: process_run,
        kind: "process_wait",
        fragment_prefix: "waiting for",
        sentence_prefix: "Waiting for",
        waiting: true,
        recent_progress_summary: latest_completed_process_summary || started_summary_for(process_run_summary(process_run))
      )
    end

    def latest_command_hint
      command_run = latest_completed_command_run
      return if command_run.blank?

      build_command_hint(
        command_run: command_run,
        kind: "command_recent",
        fragment_prefix: nil,
        sentence_prefix: nil,
        waiting: false,
        recent_progress_summary: command_run_summary(command_run)
      )
    end

    def latest_process_hint
      process_run = latest_completed_process_run
      return if process_run.blank?

      build_process_hint(
        process_run: process_run,
        kind: "process_recent",
        fragment_prefix: nil,
        sentence_prefix: nil,
        waiting: false,
        recent_progress_summary: process_run_summary(process_run)
      )
    end

    def build_command_hint(command_run:, kind:, fragment_prefix:, sentence_prefix:, waiting:, recent_progress_summary:)
      activity = command_run_activity(command_run)
      activity_summary = activity.fetch("summary")
      if waiting && inspection_activity?(activity_summary)
        return {
          "kind" => kind,
          "summary" => lowercase_initial(activity_summary),
          "current_focus_summary" => imperative_activity_summary(activity_summary),
          "recent_progress_summary" => recent_progress_summary,
          "command_run_public_id" => command_run.public_id,
          "tool_invocation_public_id" => command_run.tool_invocation.public_id,
          "workflow_node_public_id" => command_run.workflow_node&.public_id,
        }.compact
      end

      if waiting
        target = waiting_target(activity)

        return {
          "kind" => kind,
          "summary" => "waiting for #{target}",
          "current_focus_summary" => "Waiting for #{target}",
          "recent_progress_summary" => recent_progress_summary,
          "waiting_summary" => "Waiting for #{target} to finish.",
          "command_run_public_id" => command_run.public_id,
          "tool_invocation_public_id" => command_run.tool_invocation.public_id,
          "workflow_node_public_id" => command_run.workflow_node&.public_id,
        }.compact
      end

      fragment = activity_fragment(activity_summary)

      {
        "kind" => kind,
        "summary" => summary_fragment(fragment_prefix, fragment, activity_summary),
        "current_focus_summary" => sentence_summary(sentence_prefix, fragment, activity_summary),
        "recent_progress_summary" => recent_progress_summary,
        "waiting_summary" => waiting ? "Waiting for #{fragment} to finish." : nil,
        "command_run_public_id" => command_run.public_id,
        "tool_invocation_public_id" => command_run.tool_invocation.public_id,
        "workflow_node_public_id" => command_run.workflow_node&.public_id,
      }.compact
    end

    def build_process_hint(process_run:, kind:, fragment_prefix:, sentence_prefix:, waiting:, recent_progress_summary:)
      activity_summary = process_run_summary(process_run)
      fragment = activity_fragment(activity_summary)

      {
        "kind" => kind,
        "summary" => summary_fragment(fragment_prefix, fragment, activity_summary),
        "current_focus_summary" => sentence_summary(sentence_prefix, fragment, activity_summary),
        "recent_progress_summary" => recent_progress_summary,
        "waiting_summary" => waiting ? "Waiting for #{fragment} to finish." : nil,
        "process_run_public_id" => process_run.public_id,
        "workflow_node_public_id" => process_run.workflow_node.public_id,
      }.compact
    end

    def command_run_summary(command_run)
      command_run_activity(command_run).fetch("summary")
    end

    def command_run_activity(command_run)
      ConversationRuntime::BuildSafeActivitySummary.call(
        activity_kind: "command",
        command_line: command_run.command_line,
        lifecycle_state: command_run.lifecycle_state
      )
    end

    def process_run_summary(process_run)
      ConversationRuntime::BuildSafeActivitySummary.call(
        activity_kind: "process",
        command_line: process_run.command_line,
        lifecycle_state: process_run.lifecycle_state
      ).fetch("summary")
    end

    def activity_fragment(summary)
      lowercase_initial(summary.to_s.sub(/\A(?:Running|Ran|Starting|Started|Installing|Installed|Scaffolding|Scaffolded|Editing|Edited|Inspecting|Inspected)\s+/i, ""))
    end

    def summary_fragment(prefix, fragment, fallback_summary)
      return lowercase_initial(fallback_summary.to_s) if prefix.blank?

      "#{prefix} #{fragment}"
    end

    def sentence_summary(prefix, fragment, fallback_summary)
      return fallback_summary if prefix.blank?

      "#{prefix} #{fragment}"
    end

    def started_summary_for(summary)
      normalized = summary.to_s
      return normalized.sub(/\ARunning\b/i, "Started") if normalized.match?(/\ARunning\b/i)
      return normalized.sub(/\AStarting\b/i, "Started") if normalized.match?(/\AStarting\b/i)
      return normalized.sub(/\AInspecting\b/i, "Started inspecting") if normalized.match?(/\AInspecting\b/i)
      return normalized.sub(/\AInstalling\b/i, "Started installing") if normalized.match?(/\AInstalling\b/i)
      return normalized.sub(/\AEditing\b/i, "Started editing") if normalized.match?(/\AEditing\b/i)
      return normalized.sub(/\AScaffolding\b/i, "Started scaffolding") if normalized.match?(/\AScaffolding\b/i)

      normalized
    end

    def inspection_activity?(summary)
      summary.to_s.match?(/\A(?:Inspecting|Inspected)\b/i)
    end

    def imperative_activity_summary(summary)
      normalized = summary.to_s
      return normalized.sub(/\AInspecting\b/i, "Inspect") if normalized.match?(/\AInspecting\b/i)
      return normalized.sub(/\AInspected\b/i, "Inspect") if normalized.match?(/\AInspected\b/i)

      normalized
    end

    def lowercase_initial(text)
      return text if text.blank?

      text[0].downcase + text[1..]
    end

    def waiting_target(activity)
      location = activity["path_summary"].presence
      prefix =
        case activity["work_type"]
        when "verification"
          activity["summary"].to_s.match?(/test-and-build check/i) ? "the test-and-build check" : "the test run"
        when "build"
          "the production build"
        when "app_server"
          "the app server"
        when "preview"
          "the preview server"
        when "scaffolding"
          "the React app scaffold"
        when "dependency_setup"
          "project dependency installation"
        when "editing"
          "game file updates"
        else
          activity_fragment(activity.fetch("summary"))
        end

      return prefix if location.blank?

      "#{prefix} in #{location}"
    end

    def latest_completed_command_summary
      command_run = latest_completed_command_run
      command_run_summary(command_run) if command_run.present?
    end

    def latest_completed_process_summary
      process_run = latest_completed_process_run
      process_run_summary(process_run) if process_run.present?
    end

    def active_command_run
      @active_command_run ||= command_runs
        .where(lifecycle_state: ACTIVE_COMMAND_STATES)
        .order(started_at: :desc, created_at: :desc)
        .first
    end

    def latest_completed_command_run
      @latest_completed_command_run ||= command_runs
        .where.not(id: active_command_run&.id)
        .where(lifecycle_state: %w[completed failed interrupted canceled])
        .order(ended_at: :desc, started_at: :desc, created_at: :desc)
        .first
    end

    def active_process_run
      @active_process_run ||= process_runs
        .where(lifecycle_state: ACTIVE_PROCESS_STATES)
        .order(started_at: :desc, created_at: :desc)
        .first
    end

    def latest_completed_process_run
      @latest_completed_process_run ||= process_runs
        .where.not(id: active_process_run&.id)
        .where(lifecycle_state: %w[stopped failed lost])
        .order(ended_at: :desc, started_at: :desc, created_at: :desc)
        .first
    end

    def command_runs
      @command_runs ||= begin
        relation = CommandRun.joins(:workflow_node).where(workflow_nodes: { conversation_id: @conversation.id })
        relation = relation.where(workflow_node: workflow_nodes) if workflow_nodes.present?
        relation
      end
    end

    def process_runs
      @process_runs ||= begin
        relation = ProcessRun.where(conversation: @conversation)
        relation = relation.where(workflow_node: workflow_nodes) if workflow_nodes.present?
        relation
      end
    end

    def workflow_nodes
      return @workflow_nodes if instance_variable_defined?(:@workflow_nodes)

      @workflow_nodes = workflow_run&.workflow_nodes
    end

    def workflow_run
      return @workflow_run if instance_variable_defined?(:@workflow_run)

      @workflow_run = @conversation.workflow_runs.order(created_at: :desc).first
    end
  end
end
