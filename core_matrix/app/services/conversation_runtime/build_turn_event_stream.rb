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
          "actor_type" => "acceptance_harness",
          "actor_label" => "harness",
          "actor_public_id" => nil,
          "phase" => "plan",
          "family" => "runtime_progress",
          "kind" => "phase_event",
          "status" => "observed",
          "summary" => phase.to_s.tr("_", " ").capitalize,
          "detail" => nil,
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
          "actor_type" => "main_agent",
          "actor_label" => "main",
          "actor_public_id" => nil,
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
          "tool_invocation_public_id" => payload["tool_invocation_id"],
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
      node_type = entry["node_type"].to_s

      case node_type
      when "tool_call"
        "Finished a tool-backed workflow step"
      else
        "Updated the current workflow step"
      end
    end

    def workflow_step_detail(entry)
      payload = entry["payload"] || {}
      parts = []
      parts << "State `#{payload["state"]}`." if payload["state"].present?
      parts << "Tool invocation `#{payload["tool_invocation_id"]}`." if payload["tool_invocation_id"].present?
      parts.join(" ").presence
    end

    def summarize_tool_invocation(tool_invocation)
      tool_name = tool_invocation["tool_name"].to_s
      arguments = tool_invocation.dig("request_payload", "arguments") || {}

      case tool_name
      when "workspace_tree"
        {
          "phase" => "plan",
          "summary" => "Inspected the workspace tree",
          "detail" => "Path `#{arguments["path"] || "/workspace"}`.",
        }
      when "workspace_write", "workspace_patch"
        {
          "phase" => "build",
          "summary" => "Edited workspace files",
          "detail" => "Path `#{arguments["path"] || "unknown"}`.",
        }
      else
        nil
      end
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
