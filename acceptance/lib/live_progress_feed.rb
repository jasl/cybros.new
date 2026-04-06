require "fileutils"
require "json"
require "set"

module Acceptance
  module LiveProgressFeed
    module_function

    def capture!(artifact_dir:, workflow_run:, seen_event_keys:)
      workflow_node_events = workflow_run.workflow_node_events
        .includes(workflow_node: { tool_invocations: :tool_definition })
        .order(:created_at, :workflow_node_ordinal, :ordinal)
        .map { |event| serialize_workflow_node_event(event) }

      new_events = build_entries(
        workflow_node_events: workflow_node_events,
        seen_event_keys: seen_event_keys
      )

      new_events.each do |entry|
        append_jsonl(artifact_dir.join("live-progress-events.jsonl"), entry)
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
