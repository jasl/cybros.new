module ConversationRuntime
  class BuildTurnEventStream
    SEGMENT_ORDER = %w[plan build validate deliver].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation_id:, turn_id:, phase_events:, workflow_node_events:, usage_events:, tool_invocations:, command_runs:, process_runs:, subagent_sessions:, subagent_runtime_snapshots: [], agent_task_runs:, supervision_trace:, summary:)
      @conversation_id = conversation_id
      @turn_id = turn_id
      @phase_events = Array(phase_events)
      @workflow_node_events = Array(workflow_node_events)
      @usage_events = Array(usage_events)
      @tool_invocations = Array(tool_invocations)
      @command_runs = Array(command_runs)
      @process_runs = Array(process_runs)
      @subagent_sessions = Array(subagent_sessions)
      @subagent_runtime_snapshots = Array(subagent_runtime_snapshots)
      @agent_task_runs = Array(agent_task_runs)
      @supervision_trace = supervision_trace || {}
      @summary = summary || {}
    end

    def call
      timeline = build_timeline
      lanes = build_lanes(timeline)

      {
        "conversation_id" => @conversation_id,
        "turn_id" => @turn_id,
        "summary" => {
          "benchmark_outcome" => @summary["benchmark_outcome"],
          "workload_outcome" => @summary["workload_outcome"],
          "system_behavior_outcome" => @summary["system_behavior_outcome"],
          "event_count" => timeline.length,
          "lane_count" => lanes.length,
        }.compact,
        "lanes" => lanes,
        "segments" => build_segments(timeline),
        "timeline" => timeline,
      }
    end

    private

    def build_timeline
      subagent_labels = build_subagent_labels(@subagent_sessions)
      agent_task_runs_by_id = @agent_task_runs.each_with_object({}) do |task_run, memo|
        memo[task_run["agent_task_run_id"]] = task_run
      end
      tool_invocations_by_id = @tool_invocations.each_with_object({}) do |tool_invocation, memo|
        tool_id = tool_invocation["tool_invocation_public_id"] || tool_invocation["tool_invocation_id"]
        memo[tool_id] = tool_invocation
      end

      timeline = []
      timeline.concat(build_phase_events)
      timeline.concat(build_workflow_node_events)
      timeline.concat(build_tool_events(subagent_labels:, agent_task_runs_by_id:))
      timeline.concat(build_command_events(tool_invocations_by_id:, subagent_labels:, agent_task_runs_by_id:))
      timeline.concat(build_process_events(tool_invocations_by_id:, subagent_labels:, agent_task_runs_by_id:))
      timeline.concat(build_provider_round_events)
      timeline.concat(build_subagent_events(subagent_labels:))
      timeline.concat(build_subagent_runtime_snapshot_events(subagent_labels:))
      timeline.concat(build_supervision_events)

      timeline
        .compact
        .sort_by do |event|
          [
            parse_time(event["timestamp"]) || Time.at(0).utc,
            event.fetch("sort_order", 99),
            event.fetch("summary"),
          ]
        end
        .each_with_index
        .map do |event, index|
          event.except("sort_order").merge("sequence" => index + 1)
        end
    end

    def build_segments(timeline)
      SEGMENT_ORDER.filter_map do |segment|
        entries = timeline.select { |event| event["phase"] == segment }
        next if entries.empty?

        {
          "key" => segment,
          "title" => segment.to_s.capitalize,
          "events" => entries,
        }
      end
    end

    def build_lanes(timeline)
      timeline.each_with_object({}) do |event, memo|
        key = [event["actor_type"], event["actor_label"]]
        memo[key] ||= {
          "actor_type" => event["actor_type"],
          "actor_label" => event["actor_label"],
          "actor_public_id" => event["actor_public_id"],
        }
      end.values
    end

    def build_phase_events
      @phase_events.filter_map do |entry|
        phase = entry["phase"]
        next if phase.blank?

        {
          "timestamp" => entry["timestamp"],
          "actor_type" => phase_actor_type(phase),
          "actor_label" => phase_actor_label(phase),
          "actor_public_id" => nil,
          "phase" => phase_segment(phase),
          "family" => "runtime_progress",
          "kind" => "phase_event",
          "status" => phase_status(phase, entry),
          "summary" => phase_summary(phase, entry),
          "detail" => phase_detail(phase, entry),
          "source_refs" => ["phase-events.jsonl"],
          "sort_order" => 10,
        }
      end
    end

    def build_workflow_node_events
      @workflow_node_events.filter_map do |entry|
        workflow_node_key = entry["workflow_node_key"].to_s
        next if workflow_node_key.blank?

        payload = entry["payload"] || {}
        state = payload["state"].presence || entry["event_kind"].to_s

        {
          "timestamp" => entry["created_at"] || entry["updated_at"] || entry["occurred_at"],
          "actor_type" => entry["actor_type"].presence || "main_agent",
          "actor_label" => entry["actor_label"].presence || "main",
          "actor_public_id" => entry["actor_public_id"],
          "phase" => workflow_phase(workflow_node_key),
          "family" => "runtime_progress",
          "kind" => "workflow_step_#{normalize_state(state)}",
          "status" => normalize_state(state),
          "summary" => workflow_step_summary(entry),
          "detail" => workflow_step_detail(entry),
          "workflow_run_public_id" => entry["workflow_run_public_id"],
          "workflow_node_public_id" => entry["workflow_node_public_id"],
          "workflow_node_key" => workflow_node_key,
          "workflow_node_ordinal" => entry["workflow_node_ordinal"],
          "node_type" => entry["node_type"],
          "tool_invocation_public_id" => payload["tool_invocation_id"],
          "command_run_public_id" => entry["command_run_public_id"] || payload["command_run_public_id"],
          "source_refs" => ["workflow_node_events.json"],
          "sort_order" => 20,
        }
      end
    end

    def build_tool_events(subagent_labels:, agent_task_runs_by_id:)
      @tool_invocations.filter_map do |tool_invocation|
        actor = actor_for_event(tool_invocation, subagent_labels:, agent_task_runs_by_id:)
        tool_id = tool_invocation["tool_invocation_public_id"] || tool_invocation["tool_invocation_id"]
        payload = summarize_tool_invocation(tool_invocation)
        next if payload.blank?

        payload.merge(
          "timestamp" => tool_invocation["finished_at"] || tool_invocation["started_at"],
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "family" => "tool_activity",
          "kind" => "tool_completed",
          "status" => tool_invocation["status"],
          "tool_invocation_public_id" => tool_id,
          "source_refs" => ["tool_invocations.json"],
          "sort_order" => 30,
        )
      end
    end

    def build_command_events(tool_invocations_by_id:, subagent_labels:, agent_task_runs_by_id:)
      @command_runs.filter_map do |command_run|
        next if command_run["command_line"].blank?

        tool_invocation = tool_invocations_by_id[command_run["tool_invocation_id"]]
        actor = actor_for_event(tool_invocation || command_run, subagent_labels:, agent_task_runs_by_id:)
        summary = BuildSafeActivitySummary.call(
          activity_kind: "command",
          command_line: command_run["command_line"],
          lifecycle_state: command_run["lifecycle_state"]
        )

        summary.merge(
          "timestamp" => command_run["ended_at"] || command_run["started_at"],
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "family" => "command_activity",
          "kind" => "command_#{normalize_state(command_run["lifecycle_state"])}",
          "status" => normalize_state(command_run["lifecycle_state"]),
          "command_run_public_id" => command_run["command_run_public_id"] || command_run["command_run_id"],
          "tool_invocation_public_id" => tool_invocation && (tool_invocation["tool_invocation_public_id"] || tool_invocation["tool_invocation_id"]),
          "workflow_node_key" => command_run["workflow_node_key"] || tool_invocation&.dig("workflow_node_key"),
          "source_refs" => ["command_runs.json"],
          "sort_order" => 40,
        )
      end
    end

    def build_process_events(tool_invocations_by_id:, subagent_labels:, agent_task_runs_by_id:)
      @process_runs.filter_map do |process_run|
        next if process_run["command_line"].blank?

        tool_invocation = tool_invocations_by_id[process_run["tool_invocation_id"]]
        actor = actor_for_event(tool_invocation || process_run, subagent_labels:, agent_task_runs_by_id:)
        summary = BuildSafeActivitySummary.call(
          activity_kind: "process",
          command_line: process_run["command_line"],
          lifecycle_state: process_run["lifecycle_state"]
        )

        summary.merge(
          "timestamp" => process_run["ended_at"] || process_run["started_at"],
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "family" => "process_activity",
          "kind" => "process_#{normalize_state(process_run["lifecycle_state"])}",
          "status" => normalize_state(process_run["lifecycle_state"]),
          "process_run_public_id" => process_run["process_run_public_id"] || process_run["process_run_id"],
          "tool_invocation_public_id" => tool_invocation && (tool_invocation["tool_invocation_public_id"] || tool_invocation["tool_invocation_id"]),
          "source_refs" => ["process_runs.json"],
          "sort_order" => 50,
        )
      end
    end

    def build_provider_round_events
      @usage_events.filter_map do |event|
        workflow_node_key = event["workflow_node_key"].to_s
        next if workflow_node_key.blank?
        next unless workflow_node_key == "turn_step" || workflow_node_key.start_with?("provider_round_")

        {
          "timestamp" => event["occurred_at"],
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
          "phase" => workflow_phase(workflow_node_key),
          "family" => "runtime_progress",
          "kind" => "planning_step_completed",
          "status" => "completed",
          "summary" => "Prepared the next implementation step",
          "detail" => "#{event["provider_handle"]}/#{event["model_ref"]} produced #{event["output_tokens"] || 0} output tokens.",
          "workflow_node_key" => workflow_node_key,
          "source_refs" => ["usage_events.json"],
          "sort_order" => 15,
        }
      end
    end

    def build_subagent_events(subagent_labels:)
      @subagent_sessions.flat_map do |session|
        actor_label = subagent_labels.fetch(session["subagent_session_id"], "subagent")
        [
          {
            "timestamp" => session["created_at"],
            "actor_type" => "subagent",
            "actor_label" => actor_label,
            "actor_public_id" => session["subagent_session_id"],
            "phase" => "build",
            "family" => "subagent_progress",
            "kind" => "subagent_started",
            "status" => "started",
            "summary" => "#{actor_label} started delegated work",
            "detail" => nil,
            "subagent_session_public_id" => session["subagent_session_id"],
            "source_refs" => ["subagent_sessions.json"],
            "sort_order" => 60,
          },
          if session["observed_status"].present?
            {
              "timestamp" => session["updated_at"] || session["created_at"],
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => session["subagent_session_id"],
              "phase" => "build",
              "family" => "subagent_progress",
              "kind" => "subagent_completed",
              "status" => session["observed_status"],
              "summary" => "#{actor_label} completed its assigned work",
              "detail" => nil,
              "subagent_session_public_id" => session["subagent_session_id"],
              "source_refs" => ["subagent_sessions.json"],
              "sort_order" => 70,
            }
          end,
        ].compact
      end
    end

    def build_subagent_runtime_snapshot_events(subagent_labels:)
      @subagent_runtime_snapshots.flat_map do |snapshot|
        actor_label = subagent_labels.fetch(snapshot["subagent_session_id"], snapshot["profile_key"].presence || "subagent")
        actor_public_id = snapshot["subagent_session_id"]

        events = []
        events.concat(
          snapshot.fetch("usage_events", []).filter_map do |event|
            workflow_node_key = event["workflow_node_key"].to_s
            next if workflow_node_key.blank?

            {
              "timestamp" => event["occurred_at"],
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "phase" => workflow_phase(workflow_node_key),
              "family" => "subagent_progress",
              "kind" => "planning_step_completed",
              "status" => "completed",
              "summary" => "Prepared the next implementation step",
              "detail" => "#{event["provider_handle"]}/#{event["model_ref"]} produced #{event["output_tokens"] || 0} output tokens.",
              "workflow_node_key" => workflow_node_key,
              "subagent_session_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json"],
              "sort_order" => 80,
            }
          end
        )
        events.concat(
          snapshot.fetch("tool_invocations", []).filter_map do |tool_invocation|
            payload = summarize_tool_invocation(tool_invocation)
            next if payload.blank?

            payload.merge(
              "timestamp" => tool_invocation["finished_at"] || tool_invocation["started_at"],
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "family" => "tool_activity",
              "kind" => "tool_completed",
              "status" => tool_invocation["status"],
              "tool_invocation_public_id" => tool_invocation["tool_invocation_public_id"] || tool_invocation["tool_invocation_id"],
              "subagent_session_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json"],
              "sort_order" => 85,
            )
          end
        )
        events.concat(
          snapshot.fetch("command_runs", []).filter_map do |command_run|
            summary = BuildSafeActivitySummary.call(
              activity_kind: "command",
              command_line: command_run["command_line"],
              lifecycle_state: command_run["lifecycle_state"]
            )

            summary.merge(
              "timestamp" => command_run["ended_at"] || command_run["started_at"],
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "family" => "command_activity",
              "kind" => "command_#{normalize_state(command_run["lifecycle_state"])}",
              "status" => normalize_state(command_run["lifecycle_state"]),
              "command_run_public_id" => command_run["command_run_public_id"] || command_run["command_run_id"],
              "subagent_session_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json"],
              "sort_order" => 90,
            )
          end
        )
        events
      end
    end

    def build_supervision_events
      []
    end

    def workflow_step_summary(entry)
      return entry["summary"] if entry["summary"].present?

      payload = entry["payload"] || {}
      state = normalize_state(payload["state"] || entry["event_kind"])
      if payload["tool_name"] == "command_run_wait" && payload["command_summary"].present?
        prefix =
          case state
          when "started"
            "Waiting for"
          when "completed"
            "Finished"
          when "failed"
            "Failed"
          else
            "Observed"
          end
        return "#{prefix} #{payload["command_summary"]}"
      end

      node_type = entry["node_type"].to_s

      return "Queued the next implementation step" if entry["event_kind"] == "yield_requested"

      case node_type
      when "tool_call"
        state == "started" ? "Started a tool-backed workflow step" : "Finished a tool-backed workflow step"
      else
        "Updated the current workflow step"
      end
    end

    def workflow_step_detail(entry)
      return entry["detail"] if entry["detail"].present?

      payload = entry["payload"] || {}
      tool_name = entry["tool_name"].presence || payload["tool_name"].presence
      safe_tool_detail = safe_tool_detail(tool_name:, payload:)
      return safe_tool_detail if safe_tool_detail.present?

      state = normalize_state(payload["state"] || entry["event_kind"])
      return if state.blank?

      case state
      when "started"
        "This workflow step just started."
      when "completed"
        "This workflow step finished."
      when "failed"
        "This workflow step failed."
      when "waiting", "blocked"
        "This workflow step is waiting on a dependency."
      else
        "This workflow step updated."
      end
    end

    def safe_tool_detail(tool_name:, payload:)
      return if tool_name.blank?

      ConversationRuntime::BuildSafeToolInvocationSummary.call(
        tool_name: tool_name,
        arguments: payload.dig("request_payload", "arguments") || payload["arguments"] || {},
        response_payload: payload["response_payload"] || {},
        command_summary: payload["command_summary"]
      )&.fetch("detail", nil)
    end

    def summarize_tool_invocation(tool_invocation)
      ConversationRuntime::BuildSafeToolInvocationSummary.call(
        tool_name: tool_invocation["tool_name"],
        arguments: tool_invocation.dig("request_payload", "arguments") || {},
        response_payload: tool_invocation["response_payload"] || {}
      )&.slice("phase", "summary", "detail")
    end

    def actor_for_event(entry, subagent_labels:, agent_task_runs_by_id:)
      return { "actor_type" => "main_agent", "actor_label" => "main", "actor_public_id" => nil } if entry.blank?

      task_run = agent_task_runs_by_id[entry["agent_task_run_id"]]
      subagent_session_id = task_run&.fetch("subagent_session_id", nil)
      subagent_label = subagent_labels[subagent_session_id]
      return { "actor_type" => "subagent", "actor_label" => subagent_label, "actor_public_id" => subagent_session_id } if subagent_label.present?

      { "actor_type" => "main_agent", "actor_label" => "main", "actor_public_id" => nil }
    end

    def build_subagent_labels(subagent_sessions)
      counts = Hash.new(0)

      subagent_sessions.sort_by { |session| parse_time(session["created_at"]) || Time.at(0).utc }.each_with_object({}) do |session, memo|
        profile_key = session["profile_key"].presence || "subagent"
        counts[profile_key] += 1
        memo[session["subagent_session_id"]] = "#{profile_key}##{counts[profile_key]}"
      end
    end

    def workflow_phase(workflow_node_key)
      workflow_node_key.to_s.match?(/\Aprovider_round_(1|2|3)\z/) || workflow_node_key == "turn_step" ? "plan" : "build"
    end

    def phase_actor_type(phase)
      case phase
      when /\Ahost_validation/, "attempt_succeeded"
        "host_validator"
      when "supervision_progress", "supervision_complete"
        "supervisor"
      else
        "acceptance_harness"
      end
    end

    def phase_actor_label(phase)
      case phase
      when /\Ahost_validation/, "attempt_succeeded"
        "host"
      when "supervision_progress", "supervision_complete"
        "supervisor"
      else
        "harness"
      end
    end

    def phase_segment(phase)
      case phase
      when "skill_sources_prepared", "skills_validated", "conversation_initialized", "attempt_started"
        "plan"
      when "supervision_progress", "repair_prompt_prepared"
        "build"
      when "supervision_complete", "export_roundtrip_started", "benchmark_reporting_started", "benchmark_reporting_complete"
        "deliver"
      when "host_validation_started", "host_validation_complete", "attempt_succeeded"
        "validate"
      else
        "plan"
      end
    end

    def phase_status(phase, entry)
      case phase
      when "supervision_progress"
        "updated"
      when "host_validation_complete"
        host_validation_failed_checks(entry).empty? ? "completed" : "failed"
      when "benchmark_reporting_complete", "attempt_succeeded"
        "completed"
      else
        "started"
      end
    end

    def phase_summary(phase, entry)
      case phase
      when "supervision_progress"
        focus =
          entry["primary_turn_todo_plan_current_item_title"].presence ||
          entry["latest_turn_feed_summary"].presence ||
          entry["current_focus_summary"].presence ||
          entry["recent_progress_summary"].presence ||
          "No additional focus summary"
        "Supervisor checkpoint: #{focus}"
      when "attempt_started"
        "Started attempt #{entry["attempt_no"]} of #{entry["max_turn_attempts"]}"
      when "host_validation_complete"
        if host_validation_failed_checks(entry).empty?
          "Host validation passed: tests, build, preview, and Playwright"
        else
          "Host validation found issues with #{host_validation_failed_checks(entry).join(", ")}"
        end
      when "attempt_succeeded"
        "Attempt #{entry["attempt_no"]} satisfied runtime and host checks"
      when "supervision_complete"
        "Supervisor observed the turn settle after #{entry["poll_count"]} polls"
      else
        phase.to_s.tr("_", " ").capitalize
      end
    end

    def phase_detail(phase, entry)
      case phase
      when "supervision_progress"
        parts = []
        parts << "Machine state `#{entry["overall_state"]}`." if entry["overall_state"].present?
        parts << "Current plan item: #{entry["primary_turn_todo_plan_current_item_title"]}." if entry["primary_turn_todo_plan_current_item_title"].present?
        parts << "Latest turn-feed event: #{entry["latest_turn_feed_summary"]}." if entry["latest_turn_feed_summary"].present?
        parts << "Recent progress: #{entry["recent_progress_summary"]}." if entry["recent_progress_summary"].present?
        parts << "Active subagents: #{entry["active_subagent_count"]}." if entry["active_subagent_count"].present?
        parts.join(" ").presence
      when "host_validation_complete"
        passed_checks = host_validation_checks(entry).select { |_key, value| value }.keys
        failed_checks = host_validation_failed_checks(entry)

        if failed_checks.empty?
          "Host checks succeeded for #{passed_checks.join(", ")}."
        else
          details = []
          details << "passed: #{passed_checks.join(", ")}" if passed_checks.any?
          details << "failed: #{failed_checks.join(", ")}"
          "Host validation outcome: #{details.join(" | ")}."
        end
      when "supervision_complete"
        "Final observed machine state was `#{entry["overall_state"]}`."
      end
    end

    def host_validation_checks(entry)
      {
        "tests" => entry["npm_test_passed"],
        "build" => entry["npm_build_passed"],
        "preview" => entry["preview_reachable"],
        "Playwright" => entry["playwright_verification_passed"],
      }
    end

    def host_validation_failed_checks(entry)
      host_validation_checks(entry).select { |_key, value| value == false }.keys
    end

    def normalize_state(value)
      case value.to_s
      when "completed", "succeeded"
        "completed"
      when "running", "started"
        "started"
      when "failed"
        "failed"
      else
        value.to_s.presence || "observed"
      end
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
