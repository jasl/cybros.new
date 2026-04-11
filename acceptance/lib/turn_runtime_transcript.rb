module Acceptance
  module TurnRuntimeTranscript
    module_function

    SEGMENT_ORDER = %w[plan build runtime validate deliver].freeze

    def build(conversation_id:, turn_id:, phase_events:, workflow_node_events:, usage_events:, tool_invocations:, command_runs:, process_runs:, subagent_connections:, subagent_runtime_snapshots: [], agent_task_runs:, supervision_trace:, summary:)
      report = ConversationRuntime::BuildTurnEventStream.call(
        conversation_id: conversation_id,
        turn_id: turn_id,
        phase_events: phase_events,
        workflow_node_events: workflow_node_events,
        usage_events: usage_events,
        tool_invocations: tool_invocations,
        command_runs: command_runs,
        process_runs: process_runs,
        subagent_connections: subagent_connections,
        subagent_runtime_snapshots: subagent_runtime_snapshots,
        agent_task_runs: agent_task_runs,
        supervision_trace: supervision_trace,
        summary: summary
      )

      report.merge(
        "counts" => {
          "phase_event_count" => Array(phase_events).length,
          "tool_event_count" => Array(tool_invocations).length,
          "command_event_count" => Array(command_runs).length,
          "process_event_count" => Array(process_runs).length,
          "provider_round_count" => Array(usage_events).count { |event| event["workflow_node_key"].to_s.match?(/\A(provider_round_|turn_step\z)/) },
          "subagent_connection_count" => Array(subagent_connections).length,
          "subagent_runtime_snapshot_count" => Array(subagent_runtime_snapshots).length,
          "has_subagent_lane" => report.fetch("lanes").any? { |lane| lane["actor_type"] == "subagent" },
        }
      )
    end

    def to_markdown(report)
      lines = [
        "# Turn Runtime Transcript",
        "",
        "- Benchmark outcome: `#{report.dig("summary", "benchmark_outcome")}`",
        "- Workload outcome: `#{report.dig("summary", "workload_outcome")}`",
        "- System behavior outcome: `#{report.dig("summary", "system_behavior_outcome")}`",
        "- Lanes: `#{report.fetch("lanes").map { |lane| lane.fetch("actor_label") }.join("`, `")}`",
        "- Events: `#{report.dig("summary", "event_count")}`",
        "",
      ]

      report.fetch("segments").each do |segment|
        lines << "## #{segment.fetch("title")}"
        lines << ""
        segment.fetch("events").each do |event|
          time = format_timestamp(event["timestamp"])
          lines << "- `#{time}` [#{event.fetch("actor_label")}] #{event.fetch("summary")}"
          detail = event["detail"].to_s.strip
          lines << "  #{detail}" if detail.present?
        end
        lines << ""
      end

      lines.join("\n").rstrip + "\n"
    end

    private_class_method def build_phase_events(phase_events)
      phase_events.filter_map do |entry|
        phase = entry["phase"]
        next if phase.blank?

        {
          "timestamp" => entry["timestamp"],
          "actor_type" => phase_actor_type(phase),
          "actor_label" => phase_actor_label(phase),
          "actor_public_id" => nil,
          "phase" => phase_segment(phase),
          "kind" => "phase",
          "status" => phase_status(phase, entry),
          "summary" => phase_summary(phase, entry),
          "detail" => phase_detail(phase, entry),
          "source_refs" => ["phase-events.jsonl"],
          "sort_order" => 10,
        }
      end
    end

    private_class_method def build_workflow_node_progress_events(workflow_node_events)
      Array(workflow_node_events).filter_map do |entry|
        event_kind = entry["event_kind"].to_s
        workflow_node_key = entry["workflow_node_key"].to_s
        next if workflow_node_key.blank?
        next unless %w[status yield_requested node_started node_completed].include?(event_kind)

        payload = entry["payload"] || {}
        state = payload["state"].presence || event_kind
        summary =
          case event_kind
          when "yield_requested"
            "Queued follow-up work after #{workflow_node_key}"
          when "status", "node_started", "node_completed"
            state =
              case event_kind
              when "node_started" then "running"
              when "node_completed" then "completed"
              else state
              end
            "#{state.capitalize} #{node_kind_label(entry["node_type"])} node #{workflow_node_key}"
          end

        detail =
          if event_kind == "yield_requested"
            accepted_node_keys = Array(payload["accepted_node_keys"])
            accepted_detail = accepted_node_keys.any? ? "Accepted nodes: #{accepted_node_keys.join(", ")}." : nil
            [accepted_detail].compact.join(" ")
          else
            detail_parts = []
            detail_parts << "tool invocation `#{payload["tool_invocation_id"]}`." if payload["tool_invocation_id"].present?
            detail_parts << "provider request `#{payload["provider_request_id"]}`." if payload["provider_request_id"].present?
            detail_parts.presence&.join(" ")
          end

        {
          "timestamp" => entry["created_at"] || entry["updated_at"],
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
          "phase" => workflow_node_phase(entry),
          "kind" => "workflow_node_event",
          "status" => state,
          "summary" => summary,
          "detail" => detail,
          "source_refs" => ["workflow_node_events.json"],
          "sort_order" => 30,
        }
      end
    end

    private_class_method def build_subagent_events(subagent_connections, subagent_labels:)
      Array(subagent_connections).flat_map do |session|
        actor_label = subagent_labels.fetch(session["subagent_connection_id"], "subagent")
        created_event = {
          "timestamp" => session["created_at"],
          "actor_type" => "subagent",
          "actor_label" => actor_label,
          "actor_public_id" => session["subagent_connection_id"],
          "phase" => "build",
          "kind" => "subagent_spawned",
          "status" => "started",
          "summary" => "#{actor_label} started delegated work",
          "detail" => "Profile `#{session["profile_key"] || "unknown"}` opened with scope `#{session["scope"] || "unknown"}`.",
          "source_refs" => ["subagent_connections.json"],
          "sort_order" => 25,
        }

        close_status = session["observed_status"] || session["close_state"]
        completed_event =
          if close_status.present?
            {
              "timestamp" => session["updated_at"] || session["created_at"],
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => session["subagent_connection_id"],
              "phase" => "build",
              "kind" => "subagent_update",
              "status" => close_status,
              "summary" => "#{actor_label} completed its assigned work",
              "detail" => "Observed status `#{close_status}`.",
              "source_refs" => ["subagent_connections.json"],
              "sort_order" => 75,
            }
          end

        [created_event, completed_event].compact
      end
    end

    private_class_method def build_subagent_runtime_snapshot_events(subagent_runtime_snapshots, subagent_labels:)
      Array(subagent_runtime_snapshots).flat_map do |snapshot|
        actor_label = subagent_labels.fetch(snapshot["subagent_connection_id"], snapshot["profile_key"].presence || "subagent")
        actor_public_id = snapshot["subagent_connection_id"]

        events = []
        events.concat(
          build_provider_round_events(Array(snapshot["usage_events"])).map do |event|
            event.merge(
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json", *Array(event["source_refs"])].uniq
            )
          end
        )
        events.concat(
          build_tool_events(
            Array(snapshot["tool_invocations"]),
            subagent_labels: {},
            agent_task_runs_by_id: {}
          ).map do |event|
            event.merge(
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json", *Array(event["source_refs"])].uniq
            )
          end
        )
        events.concat(
          build_command_events(
            Array(snapshot["command_runs"]),
            tool_invocations_by_id: {},
            subagent_labels: {},
            agent_task_runs_by_id: {}
          ).map do |event|
            event.merge(
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json", *Array(event["source_refs"])].uniq
            )
          end
        )
        events.concat(
          build_process_events(
            Array(snapshot["process_runs"]),
            subagent_labels: {},
            agent_task_runs_by_id: {}
          ).map do |event|
            event.merge(
              "actor_type" => "subagent",
              "actor_label" => actor_label,
              "actor_public_id" => actor_public_id,
              "source_refs" => ["subagent-runtime-snapshots.json", *Array(event["source_refs"])].uniq
            )
          end
        )
        events
      end
    end

    private_class_method def build_tool_events(tool_invocations, subagent_labels:, agent_task_runs_by_id:)
      Array(tool_invocations).filter_map do |tool_invocation|
        summary_payload = summarize_tool_invocation(tool_invocation, subagent_labels:, agent_task_runs_by_id:)
        next if summary_payload.nil?

        summary_payload.merge(
          "timestamp" => tool_invocation["finished_at"] || tool_invocation["started_at"],
          "kind" => "tool_call",
          "status" => tool_invocation["status"],
          "source_refs" => ["tool_invocations.json"],
          "sort_order" => 40,
        )
      end
    end

    private_class_method def build_command_events(command_runs, tool_invocations_by_id:, subagent_labels:, agent_task_runs_by_id:)
      Array(command_runs).filter_map do |command_run|
        next if command_run["command_line"].blank?

        tool_invocation = tool_invocations_by_id[command_run["tool_invocation_id"]]
        actor = actor_for_event(tool_invocation, subagent_labels:, agent_task_runs_by_id:)
        summary, phase = summarize_command(command_run["command_line"])

        {
          "timestamp" => command_run["ended_at"] || command_run["started_at"],
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "phase" => phase,
          "kind" => "command_run",
          "status" => command_run["lifecycle_state"],
          "summary" => summary,
          "detail" => "`#{truncate(command_run["command_line"], 140)}`",
          "source_refs" => ["command_runs.json"],
          "sort_order" => 50,
        }
      end
    end

    private_class_method def build_process_events(process_runs, subagent_labels:, agent_task_runs_by_id:)
      Array(process_runs).filter_map do |process_run|
        next if process_run["command_line"].blank?

        actor = actor_for_event(process_run, subagent_labels:, agent_task_runs_by_id:)
        summary =
          if process_run["lifecycle_state"] == "running"
            "Started a long-running process"
          else
            "Process lifecycle changed"
          end

        {
          "timestamp" => process_run["ended_at"] || process_run["started_at"],
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "phase" => "validate",
          "kind" => "process_run",
          "status" => process_run["lifecycle_state"],
          "summary" => summary,
          "detail" => "`#{truncate(process_run["command_line"], 140)}`",
          "source_refs" => ["process_runs.json"],
          "sort_order" => 60,
        }
      end
    end

    private_class_method def build_provider_round_events(usage_events)
      Array(usage_events).filter_map do |event|
        workflow_node_key = event["workflow_node_key"].to_s
        next if workflow_node_key.blank?
        next unless workflow_node_key == "turn_step" || workflow_node_key.start_with?("provider_round_")

        round_label =
          if workflow_node_key == "turn_step"
            "initial planning round"
          else
            "provider round #{workflow_node_key.delete_prefix("provider_round_")}"
          end

        {
          "timestamp" => event["occurred_at"],
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
          "phase" => provider_phase(event["workflow_node_key"]),
          "kind" => "provider_round",
          "status" => event["success"] == false ? "failed" : "completed",
          "summary" => "Completed #{round_label}",
          "detail" => "#{event["provider_handle"]}/#{event["model_ref"]} produced #{event["output_tokens"] || 0} output tokens.",
          "source_refs" => ["usage_events.json"],
          "sort_order" => 20,
        }
      end
    end

    private_class_method def build_supervision_events(supervision_trace)
      final_response = supervision_trace.dig("final_response")
      machine_status = final_response&.dig("machine_status")
      return [] if machine_status.blank?

      feed_events = canonical_turn_feed_entries(machine_status).map do |entry|
        {
          "timestamp" => entry["occurred_at"] || supervision_snapshot_timestamp(machine_status: machine_status, supervision_trace: supervision_trace),
          "actor_type" => "supervisor",
          "actor_label" => "supervisor",
          "actor_public_id" => final_response["supervision_session_id"],
          "phase" => supervision_feed_phase(entry["event_kind"]),
          "kind" => "supervision_feed",
          "status" => supervision_feed_status(entry["event_kind"]),
          "summary" => entry["summary"],
          "detail" => supervision_feed_detail(entry),
          "source_refs" => ["supervision-polls.json", "supervision-final.json"],
          "sort_order" => 85,
        }
      end

      feed_events << {
        "timestamp" => supervision_snapshot_timestamp(machine_status: machine_status, supervision_trace: supervision_trace),
        "actor_type" => "supervisor",
        "actor_label" => "supervisor",
        "actor_public_id" => final_response["supervision_session_id"],
        "phase" => "deliver",
        "kind" => "supervision_snapshot",
        "status" => machine_status["overall_state"],
        "summary" => "Supervisor observed final machine state `#{machine_status["overall_state"]}`",
        "detail" => supervision_snapshot_detail(machine_status),
        "source_refs" => ["supervision-polls.json", "supervision-final.json"],
        "sort_order" => 90,
      }

      feed_events
    end

    private_class_method def summarize_tool_invocation(tool_invocation, subagent_labels:, agent_task_runs_by_id:)
      tool_name = tool_invocation["tool_name"].to_s
      actor = actor_for_event(tool_invocation, subagent_labels:, agent_task_runs_by_id:)
      request_arguments = tool_invocation.dig("request_payload", "arguments") || {}
      response_payload = tool_invocation["response_payload"] || {}

      case tool_name
      when "workspace_tree"
        {
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "phase" => "plan",
          "summary" => "Inspected the workspace tree",
          "detail" => "Path `#{request_arguments["path"] || "/workspace"}`.",
        }
      when "memory_search"
        {
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "phase" => "plan",
          "summary" => "Searched prior memory for relevant context",
          "detail" => "Queried persisted memory before editing the app.",
        }
      when "workspace_write"
        {
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "phase" => "build",
          "summary" => "Wrote workspace files",
          "detail" => "Path `#{request_arguments["path"] || "unknown"}`.",
        }
      when "workspace_patch"
        {
          "actor_type" => actor.fetch("actor_type"),
          "actor_label" => actor.fetch("actor_label"),
          "actor_public_id" => actor.fetch("actor_public_id"),
          "phase" => "build",
          "summary" => "Patched workspace files",
          "detail" => "Path `#{request_arguments["path"] || "unknown"}`.",
        }
      when "subagent_spawn"
        subagent_label = subagent_labels.fetch(response_payload["subagent_connection_id"], response_payload["profile_key"] || "subagent")
        {
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
          "phase" => "build",
          "summary" => "Spawned child task #{subagent_label}",
          "detail" => "Delegated with profile `#{response_payload["profile_key"] || request_arguments["profile_key"] || "unknown"}`.",
        }
      when "subagent_send"
        {
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
          "phase" => "build",
          "summary" => "Sent follow-up instructions to a subagent",
          "detail" => "The main agent refined or extended delegated work.",
        }
      when "subagent_wait"
        {
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
          "phase" => "build",
          "summary" => "Waited for subagent results",
          "detail" => "Subagent results were synchronized back into the main turn.",
        }
      else
        nil
      end
    end

    private_class_method def summarize_command(command_line)
      ["Executed a shell command", "runtime"]
    end

    private_class_method def build_subagent_labels(subagent_connections)
      counts = Hash.new(0)

      Array(subagent_connections).sort_by { |session| parse_time(session["created_at"]) || Time.at(0).utc }.each_with_object({}) do |session, memo|
        profile_key = session["profile_key"].presence || "subagent"
        counts[profile_key] += 1
        memo[session["subagent_connection_id"]] = "#{profile_key}##{counts[profile_key]}"
      end
    end

    private_class_method def actor_for_event(entry, subagent_labels:, agent_task_runs_by_id:)
      return { "actor_type" => "main_agent", "actor_label" => "main", "actor_public_id" => nil } if entry.blank?

      task_run = agent_task_runs_by_id[entry["agent_task_run_id"]]
      subagent_connection_id = task_run&.fetch("subagent_connection_id", nil)
      subagent_label = subagent_labels[subagent_connection_id]
      return { "actor_type" => "subagent", "actor_label" => subagent_label, "actor_public_id" => subagent_connection_id } if subagent_label.present?

      { "actor_type" => "main_agent", "actor_label" => "main", "actor_public_id" => nil }
    end

    private_class_method def phase_actor_type(phase)
      case phase
      when /\Ahost_validation/, "attempt_succeeded"
        "host_validator"
      when "supervision_progress", "supervision_complete"
        "supervisor"
      else
        "acceptance_harness"
      end
    end

    private_class_method def phase_actor_label(phase)
      case phase
      when /\Ahost_validation/, "attempt_succeeded"
        "host"
      when "supervision_progress", "supervision_complete"
        "supervisor"
      else
        "harness"
      end
    end

    private_class_method def phase_segment(phase)
      case phase
      when "skill_sources_prepared", "skills_validated", "conversation_initialized", "attempt_started"
        "plan"
      when "supervision_progress"
        "build"
      when "supervision_complete"
        "deliver"
      when "host_validation_started", "host_validation_complete", "attempt_succeeded"
        "validate"
      when "export_roundtrip_started", "benchmark_reporting_started", "benchmark_reporting_complete"
        "deliver"
      when "repair_prompt_prepared"
        "build"
      else
        "plan"
      end
    end

    private_class_method def phase_status(phase, entry)
      case phase
      when "supervision_progress"
        "updated"
      when "host_validation_complete"
        host_validation_passed_event?(entry) ? "completed" : "failed"
      when "benchmark_reporting_complete", "attempt_succeeded"
        "completed"
      else
        "started"
      end
    end

    private_class_method def phase_summary(phase, entry)
      case phase
      when "supervision_progress"
        focus =
          entry["primary_turn_todo_plan_current_item_title"].presence ||
          entry["latest_turn_feed_summary"].presence ||
          entry["current_focus_summary"].presence ||
          entry["recent_progress_summary"].presence ||
          "No additional focus summary"
        "Supervisor checkpoint: #{focus}"
      when "skill_sources_prepared"
        "Prepared staged skill sources"
      when "skills_validated"
        "Validated staged skills inside the runtime"
      when "conversation_initialized"
        "Created a fresh conversation and workspace context"
      when "attempt_started"
        "Started attempt #{entry["attempt_no"]} of #{entry["max_turn_attempts"]}"
      when "supervision_complete"
        "Supervisor observed the turn settle after #{entry["poll_count"]} polls"
      when "host_validation_started"
        "Started host-side validation"
      when "host_validation_complete"
        if host_validation_passed_event?(entry)
          "Host validation passed: tests, build, preview, and Playwright"
        else
          "Host validation found issues with #{host_validation_failed_checks(entry).join(', ')}"
        end
      when "attempt_succeeded"
        "Attempt #{entry["attempt_no"]} satisfied runtime and host checks"
      when "repair_prompt_prepared"
        "Prepared a rescue prompt for the next attempt"
      when "export_roundtrip_started"
        "Started export and transcript roundtrip validation"
      when "benchmark_reporting_started"
        "Started benchmark reporting projections"
      when "benchmark_reporting_complete"
        "Finished benchmark reporting"
      when "terminal_failure_recorded"
        "Recorded terminal failure details"
      else
        phase.to_s.tr("_", " ").capitalize
      end
    end

    private_class_method def phase_detail(phase, entry)
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
        passed_checks = host_validation_passed_checks(entry)
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
      when "benchmark_reporting_complete"
        "Outcome `#{entry["benchmark_outcome"]}` with workload `#{entry["workload_outcome"]}`."
      when "repair_prompt_prepared"
        reasons = Array(entry["trigger_reasons"])
        "Trigger reasons: #{reasons.join(", ")}."
      else
        nil
      end
    end

    private_class_method def provider_phase(workflow_node_key)
      workflow_node_key.to_s.match?(/\Aprovider_round_(1|2|3)\z/) || workflow_node_key == "turn_step" ? "plan" : "build"
    end

    private_class_method def canonical_turn_feed_entries(machine_status)
      Array(machine_status["turn_feed"].presence || machine_status["activity_feed"]).select do |entry|
        entry.to_h.fetch("event_kind", "").start_with?("turn_todo_")
      end
    end

    private_class_method def supervision_snapshot_timestamp(machine_status:, supervision_trace:)
      machine_status["last_progress_at"] ||
        machine_status["last_terminal_at"] ||
        canonical_turn_feed_entries(machine_status).last&.fetch("occurred_at", nil) ||
        Array(supervision_trace["polls"]).last&.dig("supervisor_message", "created_at") ||
        Time.current.iso8601
    end

    private_class_method def supervision_snapshot_detail(machine_status)
      parts = []
      current_item_title = machine_status.dig("primary_turn_todo_plan_view", "current_item", "title")
      current_item_key = machine_status.dig("primary_turn_todo_plan_view", "current_item_key")
      current_goal = machine_status.dig("primary_turn_todo_plan_view", "goal_summary")
      latest_feed_summary = canonical_turn_feed_entries(machine_status).last&.fetch("summary", nil)

      parts << "Current plan item `#{current_item_title || current_item_key}`." if current_item_title.present? || current_item_key.present?
      parts << "Goal summary: #{current_goal}." if current_goal.present?
      parts << "Latest canonical feed summary: #{latest_feed_summary}." if latest_feed_summary.present?
      parts << "Active child plans: #{Array(machine_status["active_subagent_turn_todo_plan_views"]).length}." if machine_status["active_subagent_turn_todo_plan_views"].present?
      parts.join(" ").presence || "No additional focus summary."
    end

    private_class_method def supervision_feed_phase(event_kind)
      case event_kind.to_s
      when /\Aturn_todo_item_(started|completed|blocked|failed|canceled)\z/
        "build"
      else
        "deliver"
      end
    end

    private_class_method def supervision_feed_status(event_kind)
      case event_kind.to_s
      when "turn_todo_item_started"
        "started"
      when "turn_todo_item_completed"
        "completed"
      when "turn_todo_item_blocked"
        "blocked"
      when "turn_todo_item_failed"
        "failed"
      when "turn_todo_item_canceled"
        "canceled"
      else
        "observed"
      end
    end

    private_class_method def supervision_feed_detail(entry)
      details_payload = entry.to_h.fetch("details_payload", {}).to_h
      parts = []
      parts << "Plan item `#{details_payload["title"] || details_payload["item_key"]}`." if details_payload["title"].present? || details_payload["item_key"].present?
      parts << "Current item key `#{details_payload["current_item_key"]}`." if details_payload["current_item_key"].present?
      parts << "Status `#{details_payload["previous_status"]}` -> `#{details_payload["current_status"]}`." if details_payload["previous_status"].present? || details_payload["current_status"].present?
      parts.join(" ").presence
    end

    private_class_method def workflow_node_phase(entry)
      workflow_node_key = entry["workflow_node_key"].to_s
      node_type = entry["node_type"].to_s

      return provider_phase(workflow_node_key) if workflow_node_key == "turn_step" || workflow_node_key.match?(/\Aprovider_round_\d+\z/)
      return "build" if node_type == "tool_call" || workflow_node_key.include?("_tool_")
      return "build" if node_type == "barrier_join" || workflow_node_key.include?("_join_")

      "build"
    end

    private_class_method def node_kind_label(node_type)
      case node_type.to_s
      when "tool_call"
        "tool"
      when "barrier_join"
        "join"
      when "turn_step"
        "provider"
      else
        node_type.to_s.presence || "workflow"
      end
    end

    private_class_method def host_validation_checks(entry)
      {
        "tests" => entry["npm_test_passed"],
        "build" => entry["npm_build_passed"],
        "preview" => entry["preview_reachable"],
        "Playwright" => entry["playwright_verification_passed"],
      }
    end

    private_class_method def host_validation_passed_event?(entry)
      host_validation_failed_checks(entry).empty?
    end

    private_class_method def host_validation_passed_checks(entry)
      host_validation_checks(entry).select { |_key, value| value }.keys
    end

    private_class_method def host_validation_failed_checks(entry)
      host_validation_checks(entry).select { |_key, value| value == false }.keys
    end

    private_class_method def segment_title(segment)
      {
        "plan" => "Plan",
        "build" => "Build",
        "validate" => "Validate",
        "deliver" => "Deliver",
      }.fetch(segment, segment.to_s.capitalize)
    end

    private_class_method def truncate(value, max_length)
      value = value.to_s
      return value if value.length <= max_length

      "#{value[0, max_length - 3]}..."
    end

    private_class_method def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    private_class_method def format_timestamp(value)
      timestamp = parse_time(value)
      return "unknown" if timestamp.nil?

      timestamp.utc.strftime("%H:%M:%S")
    end
  end
end
