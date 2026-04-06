module ConversationDiagnostics
  class RecomputeConversationSnapshot
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation = Conversation
        .includes(:workspace, turns: [:workflow_run, { conversation: :workspace }])
        .find(@conversation.id)
      turn_snapshots = conversation.turns.sort_by(&:sequence).map do |turn|
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
      snapshot.cached_input_tokens_total = sum(turn_snapshots, :cached_input_tokens_total)
      snapshot.prompt_cache_available_event_count = sum(turn_snapshots, :prompt_cache_available_event_count)
      snapshot.prompt_cache_unknown_event_count = sum(turn_snapshots, :prompt_cache_unknown_event_count)
      snapshot.prompt_cache_unsupported_event_count = sum(turn_snapshots, :prompt_cache_unsupported_event_count)
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
      snapshot.estimated_cost_event_count = sum(turn_snapshots, :estimated_cost_event_count)
      snapshot.estimated_cost_missing_event_count = sum(turn_snapshots, :estimated_cost_missing_event_count)
      snapshot.attributed_user_estimated_cost_event_count = sum(turn_snapshots, :attributed_user_estimated_cost_event_count)
      snapshot.attributed_user_estimated_cost_missing_event_count = sum(turn_snapshots, :attributed_user_estimated_cost_missing_event_count)
      snapshot.most_expensive_turn = turn_snapshots.max_by { |item| [item.estimated_cost_total.to_d, item.turn_id] }&.turn
      snapshot.most_rounds_turn = turn_snapshots.max_by { |item| [item.provider_round_count.to_i, item.turn_id] }&.turn
      snapshot.metadata = compact_metadata(
        {
        "provider_usage_breakdown" => provider_usage_breakdown(
          UsageEvent.where(conversation_id: conversation.id)
        ),
        "attributed_user_provider_usage_breakdown" => provider_usage_breakdown(
          UsageEvent.where(conversation_id: conversation.id, user_id: conversation.workspace.user_id)
        ),
        "workflow_node_type_counts" => merge_count_hashes(turn_snapshots, "workflow_node_type_counts"),
        "tool_breakdown" => merge_nested_counts(turn_snapshots, "tool_breakdown"),
        "command_classification_counts" => merge_nested_counts(turn_snapshots, "command_classification_counts"),
        "subagent_status_counts" => merge_count_hashes(turn_snapshots, "subagent_status_counts"),
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

    def provider_usage_breakdown(scope)
      scope
        .group(:provider_handle, :model_ref, :operation_kind)
        .order(:provider_handle, :model_ref, :operation_kind)
        .pluck(
          :provider_handle,
          :model_ref,
          :operation_kind,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN success THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN success THEN 0 ELSE 1 END)"),
          Arel.sql("SUM(COALESCE(input_tokens, 0))"),
          Arel.sql("SUM(COALESCE(output_tokens, 0))"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'available' THEN COALESCE(cached_input_tokens, 0) ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'available' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'unknown' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'unsupported' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'available' THEN COALESCE(input_tokens, 0) ELSE 0 END)"),
          Arel.sql("SUM(COALESCE(estimated_cost, 0))"),
          Arel.sql("SUM(CASE WHEN estimated_cost IS NULL THEN 0 ELSE 1 END)"),
          Arel.sql("SUM(COALESCE(latency_ms, 0))"),
          Arel.sql("SUM(CASE WHEN latency_ms IS NULL THEN 0 ELSE 1 END)"),
          Arel.sql("MAX(COALESCE(latency_ms, 0))")
        )
        .map do |provider_handle, model_ref, operation_kind, event_count, success_count, failure_count, input_tokens_total, output_tokens_total, cached_input_tokens_total, prompt_cache_available_event_count, prompt_cache_unknown_event_count, prompt_cache_unsupported_event_count, prompt_cache_available_input_tokens_total, estimated_cost_total, estimated_cost_event_count, total_latency_ms, latency_event_count, max_latency_ms|
          estimated_cost_missing_event_count = event_count.to_i - estimated_cost_event_count.to_i

          {
            "provider_handle" => provider_handle,
            "model_ref" => model_ref,
            "operation_kind" => operation_kind,
            "event_count" => event_count.to_i,
            "success_count" => success_count.to_i,
            "failure_count" => failure_count.to_i,
            "input_tokens_total" => input_tokens_total.to_i,
            "output_tokens_total" => output_tokens_total.to_i,
            "cached_input_tokens_total" => cached_input_tokens_total.to_i,
            "prompt_cache_available_event_count" => prompt_cache_available_event_count.to_i,
            "prompt_cache_unknown_event_count" => prompt_cache_unknown_event_count.to_i,
            "prompt_cache_unsupported_event_count" => prompt_cache_unsupported_event_count.to_i,
            "prompt_cache_hit_rate" => prompt_cache_hit_rate(
              cached_input_tokens_total: cached_input_tokens_total,
              available_event_count: prompt_cache_available_event_count,
              available_input_tokens_total: prompt_cache_available_input_tokens_total
            ),
            "estimated_cost_total" => estimated_cost_total.to_d.to_s("F"),
            "estimated_cost_event_count" => estimated_cost_event_count.to_i,
            "estimated_cost_missing_event_count" => estimated_cost_missing_event_count,
            "latency_event_count" => latency_event_count.to_i,
            "avg_latency_ms" => latency_event_count.to_i.zero? ? 0 : (total_latency_ms.to_f / latency_event_count.to_i).round,
            "max_latency_ms" => max_latency_ms.to_i,
          }
        end
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

    def prompt_cache_hit_rate(cached_input_tokens_total:, available_event_count:, available_input_tokens_total:)
      return nil if available_event_count.to_i.zero?
      return nil if available_input_tokens_total.to_i.zero?

      cached_input_tokens_total.to_f / available_input_tokens_total.to_f
    end
  end
end
