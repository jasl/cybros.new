module ConversationDiagnostics
  class RecomputeConversationSnapshot
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation = Conversation.find(@conversation.id)
      turn_snapshots = conversation.turns.order(:sequence).map do |turn|
        ConversationDiagnostics::RecomputeTurnSnapshot.call(turn: turn)
      end

      snapshot = ConversationDiagnosticsSnapshot.find_or_initialize_by(conversation: conversation)
      snapshot.installation = conversation.installation
      snapshot.lifecycle_state = conversation.lifecycle_state
      snapshot.turn_count = turn_snapshots.length
      snapshot.active_turn_count = turn_snapshots.count { |item| item.lifecycle_state == "active" }
      snapshot.completed_turn_count = turn_snapshots.count { |item| item.lifecycle_state == "completed" }
      snapshot.failed_turn_count = turn_snapshots.count { |item| item.lifecycle_state == "failed" }
      snapshot.canceled_turn_count = turn_snapshots.count { |item| item.lifecycle_state == "canceled" }
      snapshot.usage_event_count = sum(turn_snapshots, :usage_event_count)
      snapshot.input_tokens_total = sum(turn_snapshots, :input_tokens_total)
      snapshot.output_tokens_total = sum(turn_snapshots, :output_tokens_total)
      snapshot.estimated_cost_total = decimal_sum(turn_snapshots, :estimated_cost_total)
      snapshot.attributed_user_usage_event_count = sum(turn_snapshots, :attributed_user_usage_event_count)
      snapshot.attributed_user_input_tokens_total = sum(turn_snapshots, :attributed_user_input_tokens_total)
      snapshot.attributed_user_output_tokens_total = sum(turn_snapshots, :attributed_user_output_tokens_total)
      snapshot.attributed_user_estimated_cost_total = decimal_sum(turn_snapshots, :attributed_user_estimated_cost_total)
      snapshot.provider_round_count = sum(turn_snapshots, :provider_round_count)
      snapshot.tool_call_count = sum(turn_snapshots, :tool_call_count)
      snapshot.tool_failure_count = sum(turn_snapshots, :tool_failure_count)
      snapshot.command_run_count = sum(turn_snapshots, :command_run_count)
      snapshot.command_failure_count = sum(turn_snapshots, :command_failure_count)
      snapshot.process_run_count = sum(turn_snapshots, :process_run_count)
      snapshot.process_failure_count = sum(turn_snapshots, :process_failure_count)
      snapshot.subagent_session_count = sum(turn_snapshots, :subagent_session_count)
      snapshot.input_variant_count = sum(turn_snapshots, :input_variant_count)
      snapshot.output_variant_count = sum(turn_snapshots, :output_variant_count)
      snapshot.resume_attempt_count = sum(turn_snapshots, :resume_attempt_count)
      snapshot.retry_attempt_count = sum(turn_snapshots, :retry_attempt_count)
      snapshot.most_expensive_turn = turn_snapshots.max_by { |item| [item.estimated_cost_total.to_d, item.turn_id] }&.turn
      snapshot.most_rounds_turn = turn_snapshots.max_by { |item| [item.provider_round_count.to_i, item.turn_id] }&.turn
      snapshot.metadata = compact_metadata(
        {
        "provider_usage_breakdown" => merge_provider_breakdowns(turn_snapshots),
        "attributed_user_provider_usage_breakdown" => merge_provider_breakdowns(
          turn_snapshots,
          key: "attributed_user_provider_usage_breakdown"
        ),
        "workflow_node_type_counts" => merge_count_hashes(turn_snapshots, "workflow_node_type_counts"),
        "tool_breakdown" => merge_nested_counts(turn_snapshots, "tool_breakdown"),
        "command_classification_counts" => merge_nested_counts(turn_snapshots, "command_classification_counts"),
        "subagent_status_counts" => merge_count_hashes(turn_snapshots, "subagent_status_counts"),
        "cost_summary" => merge_cost_summary(turn_snapshots),
        "attributed_user_cost_summary" => merge_cost_summary(
          turn_snapshots,
          key: "attributed_user_cost_summary"
        ),
        }
      )
      snapshot.save!
      snapshot
    end

    private

    def sum(items, attribute)
      items.sum { |item| item.public_send(attribute).to_i }
    end

    def decimal_sum(items, attribute)
      items.sum(BigDecimal("0")) { |item| item.public_send(attribute).to_d }
    end

    def merge_provider_breakdowns(items, key: "provider_usage_breakdown")
      grouped = {}

      items.each do |item|
        Array(item.metadata[key]).each do |entry|
          group_key = [entry["provider_handle"], entry["model_ref"], entry["operation_kind"]]
          grouped[group_key] ||= {
            "provider_handle" => entry["provider_handle"],
            "model_ref" => entry["model_ref"],
            "operation_kind" => entry["operation_kind"],
            "event_count" => 0,
            "success_count" => 0,
            "failure_count" => 0,
            "input_tokens_total" => 0,
            "output_tokens_total" => 0,
            "estimated_cost_total" => BigDecimal("0"),
            "estimated_cost_event_count" => 0,
            "estimated_cost_missing_event_count" => 0,
            "latency_event_count" => 0,
            "total_latency_ms" => 0,
            "max_latency_ms" => 0,
          }

          grouped[group_key]["event_count"] += entry["event_count"].to_i
          grouped[group_key]["success_count"] += entry["success_count"].to_i
          grouped[group_key]["failure_count"] += entry["failure_count"].to_i
          grouped[group_key]["input_tokens_total"] += entry["input_tokens_total"].to_i
          grouped[group_key]["output_tokens_total"] += entry["output_tokens_total"].to_i
          grouped[group_key]["estimated_cost_total"] += entry["estimated_cost_total"].to_d
          grouped[group_key]["estimated_cost_event_count"] += entry["estimated_cost_event_count"].to_i
          grouped[group_key]["estimated_cost_missing_event_count"] += entry["estimated_cost_missing_event_count"].to_i
          grouped[group_key]["latency_event_count"] += entry["latency_event_count"].to_i
          grouped[group_key]["total_latency_ms"] += entry["total_latency_ms"].to_i
          grouped[group_key]["max_latency_ms"] = [grouped[group_key]["max_latency_ms"], entry["max_latency_ms"].to_i].max
        end
      end

      grouped.values.map do |entry|
        latency_event_count = entry["latency_event_count"]

        entry.merge(
          "avg_latency_ms" => latency_event_count.zero? ? 0 : (entry["total_latency_ms"].to_f / latency_event_count).round,
          "estimated_cost_total" => entry["estimated_cost_total"].to_s("F"),
          "cost_data_available" => entry["estimated_cost_event_count"].positive?,
          "cost_data_complete" => entry["event_count"].positive? && entry["estimated_cost_missing_event_count"].zero?
        )
      end.sort_by { |entry| [entry["provider_handle"], entry["model_ref"], entry["operation_kind"]] }
    end

    def merge_count_hashes(items, key)
      items.each_with_object(Hash.new(0)) do |item, result|
        item.metadata.fetch(key, {}).each do |name, count|
          result[name] += count.to_i
        end
      end.sort.to_h
    end

    def merge_nested_counts(items, key)
      items.each_with_object({}) do |item, result|
        item.metadata.fetch(key, {}).each do |name, payload|
          result[name] ||= { "count" => 0, "failures" => 0 }
          result[name]["count"] += payload["count"].to_i
          result[name]["failures"] += payload["failures"].to_i
        end
      end.sort.to_h
    end

    def merge_cost_summary(items, key: "cost_summary")
      summary = items.each_with_object(
        {
          "estimated_cost_event_count" => 0,
          "estimated_cost_missing_event_count" => 0,
        }
      ) do |item, result|
        payload = item.metadata.fetch(key, {})
        result["estimated_cost_event_count"] += payload["estimated_cost_event_count"].to_i
        result["estimated_cost_missing_event_count"] += payload["estimated_cost_missing_event_count"].to_i
      end

      total_events = summary["estimated_cost_event_count"] + summary["estimated_cost_missing_event_count"]

      summary.merge(
        "cost_data_available" => summary["estimated_cost_event_count"].positive?,
        "cost_data_complete" => total_events.positive? && summary["estimated_cost_missing_event_count"].zero?
      )
    end

    def compact_metadata(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), memo|
          compacted = compact_metadata(nested_value)
          memo[key] = compacted unless removable_metadata_value?(compacted)
        end
      when Array
        value.filter_map do |entry|
          compacted = compact_metadata(entry)
          compacted unless removable_metadata_value?(compacted)
        end
      else
        value
      end
    end

    def removable_metadata_value?(value)
      value.nil? ||
        (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
