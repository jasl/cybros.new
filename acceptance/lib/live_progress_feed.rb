require "fileutils"
require "json"
require "set"

module Acceptance
  module LiveProgressFeed
    module_function

    def capture!(artifact_dir:, workflow_run:, seen_event_keys:, owner_conversation: nil)
      workflow_node_events = serialize_workflow_node_events_for_capture(
        workflow_run: workflow_run,
        owner_conversation: owner_conversation
      )

      new_events = build_entries(
        workflow_node_events: workflow_node_events,
        seen_event_keys: seen_event_keys
      )

      new_events.each do |entry|
        append_jsonl(artifact_dir.join("logs", "live-progress-events.jsonl"), entry)
        puts "[capstone-live] #{entry.fetch("summary")}"
      end

      {
        "new_events" => new_events,
        "seen_event_count" => seen_event_keys.length,
      }
    end

    def build_entries(workflow_node_events:, seen_event_keys:)
      Array(workflow_node_events).filter_map do |entry|
        entry = stringify_keys(entry)
        event_key = build_event_key(entry)
        next if seen_event_keys.include?(event_key)

        seen_event_keys << event_key
        normalize_event(entry)
      end.compact
    end

    def normalize_event(entry)
      if entry["summary"].present?
        return {
          "timestamp" => normalize_timestamp(entry["created_at"] || entry["updated_at"] || entry["timestamp"]),
          "kind" => inferred_live_progress_kind(entry),
          "event_kind" => entry["event_kind"],
          "actor_type" => entry["actor_type"].presence || "main_agent",
          "actor_label" => entry["actor_label"].presence || "main",
          "actor_public_id" => entry["actor_public_id"],
          "workflow_run_public_id" => entry["workflow_run_public_id"],
          "workflow_node_key" => entry["workflow_node_key"],
          "workflow_node_ordinal" => entry["workflow_node_ordinal"],
          "node_type" => entry["node_type"],
          "state" => entry["state"] || stringify_keys(entry["payload"] || {})["state"],
          "summary" => entry["summary"],
          "detail" => entry["detail"],
        }
      end

      event_kind = entry["event_kind"].to_s
      workflow_node_key = entry["workflow_node_key"].to_s
      return if workflow_node_key.blank?

      payload = stringify_keys(entry["payload"] || {})
      node_type = entry["node_type"].to_s
      state = payload["state"].presence || inferred_state(event_kind)
      return if state.blank? && event_kind != "yield_requested"

      detail =
        case event_kind
        when "yield_requested"
          accepted_nodes = Array(payload["accepted_node_keys"])
          accepted_nodes.any? ? "Accepted nodes: #{accepted_nodes.join(", ")}." : nil
        else
          parts = []
          tool_name = entry["tool_name"].presence || payload["tool_name"].presence
          parts << "Tool `#{tool_name}`." if tool_name.present?
          parts << "Tool invocation `#{payload["tool_invocation_id"]}`." if payload["tool_invocation_id"].present?
          parts << "Provider request `#{payload["provider_request_id"]}`." if payload["provider_request_id"].present?
          parts.join(" ").presence
        end

      {
        "timestamp" => normalize_timestamp(entry["created_at"] || entry["updated_at"]),
        "kind" => "workflow_live_progress",
        "event_kind" => event_kind,
        "actor_type" => entry["actor_type"].presence || "main_agent",
        "actor_label" => entry["actor_label"].presence || "main",
        "actor_public_id" => entry["actor_public_id"],
        "workflow_run_public_id" => entry["workflow_run_public_id"],
        "workflow_node_key" => workflow_node_key,
        "workflow_node_ordinal" => entry["workflow_node_ordinal"],
        "node_type" => node_type,
        "state" => state,
        "summary" => build_summary(
          event_kind: event_kind,
          node_type: node_type,
          workflow_node_key: workflow_node_key,
          state: state
        ),
        "detail" => detail,
      }
    end

    private_class_method def build_summary(event_kind:, node_type:, workflow_node_key:, state:)
      case event_kind
      when "yield_requested"
        "Queued follow-up work after #{workflow_node_key}"
      else
        "#{state.to_s.capitalize} #{node_kind_label(node_type)} node #{workflow_node_key}"
      end
    end

    private_class_method def inferred_live_progress_kind(entry)
      explicit_kind = entry["kind"].presence
      return explicit_kind if explicit_kind.present?

      event_kind = entry["event_kind"].to_s
      node_type = entry["node_type"].to_s
      actor_type = entry["actor_type"].to_s

      if event_kind.start_with?("subagent_") || node_type == "subagent_session" || actor_type == "subagent"
        "subagent_live_progress"
      else
        "workflow_live_progress"
      end
    end

    private_class_method def serialize_workflow_node_events_for_capture(workflow_run:, owner_conversation:)
      entries = serialize_workflow_run_events(
        workflow_run: workflow_run,
        actor_type: "main_agent",
        actor_label: "main",
        actor_public_id: nil
      )
      return entries if owner_conversation.blank?

      subagent_labels = build_subagent_labels(owner_conversation)
      entries.concat(build_subagent_session_progress_entries(owner_conversation, subagent_labels: subagent_labels))
      active_workflow_runs_for_subagents(owner_conversation).each do |entry|
        entries.concat(
          serialize_workflow_run_events(
            workflow_run: entry.fetch("workflow_run"),
            actor_type: "subagent",
            actor_label: subagent_labels.fetch(entry.fetch("subagent_session_id"), entry.fetch("profile_key", "subagent")),
            actor_public_id: entry.fetch("subagent_session_id")
          )
        )
      end
      entries
    end

    private_class_method def build_subagent_session_progress_entries(owner_conversation, subagent_labels:)
      owner_conversation.owned_subagent_sessions.order(:created_at, :id).flat_map do |session|
        label = subagent_labels.fetch(session.public_id, session.profile_key.presence || "subagent")
        sequence = session.attributes["supervision_sequence"] || session.updated_at&.to_i || 0
        timestamp = session.last_progress_at || session.updated_at || session.created_at
        workflow_run_public_id = WorkflowRun.where(conversation_id: session.conversation_id).order(created_at: :desc, id: :desc).pick(:public_id)

        entries = []
        if session.supervision_state.present? && session.supervision_state != "queued"
          entries << {
            "created_at" => timestamp,
            "kind" => "subagent_live_progress",
            "event_kind" => "subagent_status",
            "actor_type" => "subagent",
            "actor_label" => label,
            "actor_public_id" => session.public_id,
            "workflow_run_public_id" => workflow_run_public_id,
            "workflow_node_key" => "subagent:#{session.public_id}:status:#{sequence}",
            "workflow_node_ordinal" => 0,
            "node_type" => "subagent_session",
            "state" => session.supervision_state,
            "summary" => "#{label} is #{session.supervision_state}",
            "detail" => session.current_focus_summary.presence || session.request_summary,
          }
        end

        progress_summary = session.recent_progress_summary.presence || session.current_focus_summary.presence
        if progress_summary.present?
          entries << {
            "created_at" => timestamp,
            "kind" => "subagent_live_progress",
            "event_kind" => "subagent_progress",
            "actor_type" => "subagent",
            "actor_label" => label,
            "actor_public_id" => session.public_id,
            "workflow_run_public_id" => workflow_run_public_id,
            "workflow_node_key" => "subagent:#{session.public_id}:progress:#{sequence}",
            "workflow_node_ordinal" => 1,
            "node_type" => "subagent_session",
            "state" => session.supervision_state,
            "summary" => "#{label}: #{progress_summary}",
            "detail" => session.next_step_hint.presence || session.waiting_summary.presence || session.blocked_summary,
          }
        end

        entries
      end
    end

    private_class_method def active_workflow_runs_for_subagents(owner_conversation)
      sessions = owner_conversation.owned_subagent_sessions.includes(:conversation).order(:created_at, :id).to_a
      latest_runs_by_conversation_id = WorkflowRun.where(conversation_id: sessions.map(&:conversation_id))
        .order(created_at: :desc, id: :desc)
        .group_by(&:conversation_id)
        .transform_values(&:first)

      sessions.filter_map do |session|
        workflow_run = latest_runs_by_conversation_id[session.conversation_id]
        next if workflow_run.blank?

        {
          "subagent_session_id" => session.public_id,
          "profile_key" => session.profile_key,
          "workflow_run" => workflow_run,
        }
      end
    end

    private_class_method def build_subagent_labels(owner_conversation)
      counts = Hash.new(0)
      owner_conversation.owned_subagent_sessions.order(:created_at, :id).each_with_object({}) do |session, memo|
        profile_key = session.profile_key.presence || "subagent"
        counts[profile_key] += 1
        memo[session.public_id] = "#{profile_key}##{counts[profile_key]}"
      end
    end

    private_class_method def serialize_workflow_run_events(workflow_run:, actor_type:, actor_label:, actor_public_id:)
      workflow_run.workflow_node_events
        .includes(workflow_node: { tool_invocations: :tool_definition })
        .order(:created_at, :workflow_node_ordinal, :ordinal)
        .map do |event|
          serialize_workflow_node_event(event).merge(
            "actor_type" => actor_type,
            "actor_label" => actor_label,
            "actor_public_id" => actor_public_id
          )
        end
    end

    private_class_method def inferred_state(event_kind)
      case event_kind
      when "node_started"
        "running"
      when "node_completed"
        "completed"
      end
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

    private_class_method def build_event_key(entry)
      [
        entry["workflow_run_public_id"],
        entry["workflow_node_key"],
        entry["workflow_node_ordinal"],
        entry["ordinal"],
        entry["event_kind"],
      ].join(":")
    end

    private_class_method def serialize_workflow_node_event(event)
      tool_invocation = event.workflow_node.tool_invocations.find do |candidate|
        payload_tool_invocation_id = event.payload["tool_invocation_id"]
        payload_tool_invocation_id.present? ? candidate.public_id == payload_tool_invocation_id : true
      end

      event.attributes.slice(
        "workflow_node_key",
        "workflow_node_ordinal",
        "ordinal",
        "event_kind",
        "payload"
      ).merge(
        "workflow_run_public_id" => event.workflow_run.public_id,
        "created_at" => event.created_at.iso8601,
        "updated_at" => event.updated_at.iso8601,
        "node_type" => event.workflow_node.node_type,
        "tool_name" => tool_invocation&.tool_definition&.tool_name
      )
    end

    private_class_method def normalize_timestamp(value)
      return if value.nil?
      return value.iso8601 if value.respond_to?(:iso8601)

      Time.iso8601(value.to_s).iso8601
    rescue ArgumentError
      value.to_s
    end

    private_class_method def append_jsonl(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "a") { |file| file.puts(JSON.generate(payload)) }
    end

    private_class_method def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), memo|
          memo[key.to_s] = stringify_keys(nested_value)
        end
      when Array
        value.map { |entry| stringify_keys(entry) }
      else
        value
      end
    end
  end
end
