module ConversationDiagnostics
  class RecomputeTurnSnapshot
    RETRY_DELIVERY_KINDS = %w[step_retry paused_retry].freeze
    FAILURE_TOOL_STATES = %w[failed canceled].freeze
    FAILURE_COMMAND_STATES = %w[failed interrupted canceled].freeze
    FAILURE_PROCESS_STATES = %w[failed lost].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(turn:)
      @turn = turn
    end

    def call
      turn = load_turn(@turn)
      conversation = turn.conversation
      usage_scope = UsageEvent.where(turn_id: turn.id)
      attributed_usage_scope = usage_scope.where(user_id: turn.user_id)
      workflow_nodes = WorkflowNode.where(turn_id: turn.id)
      tool_invocations = tool_invocation_scope(turn)
      command_runs = command_run_scope(turn)
      process_runs = ProcessRun.where(turn_id: turn.id)
      subagent_connections = SubagentConnection.where(origin_turn_id: turn.id)
      workflow_node_type_counts = stringify_hash(workflow_nodes.group(:node_type).count)
      tool_breakdown = tool_breakdown(tool_invocations)
      command_state_counts = stringify_hash(command_runs.group(:lifecycle_state).count)
      process_state_counts = stringify_hash(process_runs.group(:lifecycle_state).count)
      subagent_status_counts = stringify_hash(subagent_connections.group(:observed_status).count)
      message_slot_counts = stringify_hash(turn.messages.group(:slot).count)
      task_delivery_counts = task_delivery_counts(turn)

      snapshot = TurnDiagnosticsSnapshot.find_or_initialize_by(turn: turn)
      snapshot.installation = turn.installation
      snapshot.conversation = conversation
      snapshot.lifecycle_state = turn.lifecycle_state

      usage_metrics = aggregate_usage(usage_scope)
      attributed_usage_metrics = aggregate_usage(attributed_usage_scope)

      snapshot.usage_event_count = usage_metrics.fetch("event_count")
      snapshot.input_tokens_total = usage_metrics.fetch("input_tokens_total")
      snapshot.output_tokens_total = usage_metrics.fetch("output_tokens_total")
      snapshot.estimated_cost_total = usage_metrics.fetch("estimated_cost_total")
      snapshot.cached_input_tokens_total = usage_metrics.fetch("cached_input_tokens_total")
      snapshot.prompt_cache_available_event_count = usage_metrics.fetch("prompt_cache_available_event_count")
      snapshot.prompt_cache_unknown_event_count = usage_metrics.fetch("prompt_cache_unknown_event_count")
      snapshot.prompt_cache_unsupported_event_count = usage_metrics.fetch("prompt_cache_unsupported_event_count")
      snapshot.attributed_user_usage_event_count = attributed_usage_metrics.fetch("event_count")
      snapshot.attributed_user_input_tokens_total = attributed_usage_metrics.fetch("input_tokens_total")
      snapshot.attributed_user_output_tokens_total = attributed_usage_metrics.fetch("output_tokens_total")
      snapshot.attributed_user_estimated_cost_total = attributed_usage_metrics.fetch("estimated_cost_total")
      snapshot.provider_round_count = usage_metrics.fetch("provider_round_count")
      snapshot.tool_call_count = sum_nested_counts(tool_breakdown, "count")
      snapshot.tool_failure_count = sum_nested_counts(tool_breakdown, "failures")
      snapshot.command_run_count = sum_counts(command_state_counts)
      snapshot.command_failure_count = sum_counts(command_state_counts, FAILURE_COMMAND_STATES)
      snapshot.process_run_count = sum_counts(process_state_counts)
      snapshot.process_failure_count = sum_counts(process_state_counts, FAILURE_PROCESS_STATES)
      snapshot.subagent_connection_count = sum_counts(subagent_status_counts)
      snapshot.input_variant_count = message_slot_counts.fetch("input", 0)
      snapshot.output_variant_count = message_slot_counts.fetch("output", 0)
      snapshot.resume_attempt_count = task_delivery_counts.fetch("resume_attempt_count")
      snapshot.retry_attempt_count = task_delivery_counts.fetch("retry_attempt_count")
      snapshot.avg_latency_ms = usage_metrics.fetch("avg_latency_ms")
      snapshot.max_latency_ms = usage_metrics.fetch("max_latency_ms")
      snapshot.estimated_cost_event_count = usage_metrics.fetch("estimated_cost_event_count")
      snapshot.estimated_cost_missing_event_count = usage_metrics.fetch("estimated_cost_missing_event_count")
      snapshot.attributed_user_estimated_cost_event_count = attributed_usage_metrics.fetch("estimated_cost_event_count")
      snapshot.attributed_user_estimated_cost_missing_event_count = attributed_usage_metrics.fetch("estimated_cost_missing_event_count")
      snapshot.pause_state = turn.workflow_run&.recovery_state
      snapshot.metadata = compact_metadata(
        {
          "provider_usage_breakdown" => provider_usage_breakdown(usage_scope),
          "attributed_user_provider_usage_breakdown" => provider_usage_breakdown(attributed_usage_scope),
          "prompt_cache_available_input_tokens_total" => usage_metrics.fetch("prompt_cache_available_input_tokens_total"),
          "workflow_node_type_counts" => workflow_node_type_counts,
          "tool_breakdown" => tool_breakdown,
          "command_lifecycle_state_counts" => command_state_counts,
          "subagent_status_counts" => subagent_status_counts,
        }
      )
      snapshot.save!
      snapshot
    end

    private

    def load_turn(turn)
      return Turn.includes(:installation, :workflow_run, :conversation).find(turn.id) unless turn.is_a?(Turn)

      ActiveRecord::Associations::Preloader.new(
        records: [turn],
        associations: [:installation, :workflow_run, :conversation]
      ).call
      turn
    end

    def tool_invocation_scope(turn)
      node_ids = WorkflowNode.where(turn_id: turn.id).select(:id)
      task_ids = AgentTaskRun.where(turn_id: turn.id).select(:id)

      ToolInvocation.where(workflow_node_id: node_ids)
        .or(ToolInvocation.where(agent_task_run_id: task_ids))
    end

    def command_run_scope(turn)
      node_ids = WorkflowNode.where(turn_id: turn.id).select(:id)
      task_ids = AgentTaskRun.where(turn_id: turn.id).select(:id)

      CommandRun.where(workflow_node_id: node_ids)
        .or(CommandRun.where(agent_task_run_id: task_ids))
    end

    def aggregate_usage(scope)
      event_count,
        input_tokens_total,
        output_tokens_total,
        estimated_cost_total,
        cached_input_tokens_total,
        prompt_cache_available_event_count,
        prompt_cache_unknown_event_count,
        prompt_cache_unsupported_event_count,
        avg_latency_ms,
        max_latency_ms,
        estimated_cost_event_count,
        prompt_cache_available_input_tokens_total,
        provider_round_count = scope.pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(COALESCE(input_tokens, 0))"),
          Arel.sql("SUM(COALESCE(output_tokens, 0))"),
          Arel.sql("SUM(COALESCE(estimated_cost, 0))"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'available' THEN COALESCE(cached_input_tokens, 0) ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'available' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'unknown' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'unsupported' THEN 1 ELSE 0 END)"),
          Arel.sql("AVG(latency_ms)"),
          Arel.sql("MAX(COALESCE(latency_ms, 0))"),
          Arel.sql("SUM(CASE WHEN estimated_cost IS NULL THEN 0 ELSE 1 END)"),
          Arel.sql("SUM(CASE WHEN prompt_cache_status = 'available' THEN COALESCE(input_tokens, 0) ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN operation_kind = 'text_generation' THEN 1 ELSE 0 END)")
        )
      estimated_cost_missing_event_count = event_count.to_i - estimated_cost_event_count.to_i

      {
        "event_count" => event_count.to_i,
        "input_tokens_total" => input_tokens_total.to_i,
        "output_tokens_total" => output_tokens_total.to_i,
        "estimated_cost_total" => estimated_cost_total.to_d,
        "cached_input_tokens_total" => cached_input_tokens_total.to_i,
        "prompt_cache_available_event_count" => prompt_cache_available_event_count.to_i,
        "prompt_cache_unknown_event_count" => prompt_cache_unknown_event_count.to_i,
        "prompt_cache_unsupported_event_count" => prompt_cache_unsupported_event_count.to_i,
        "avg_latency_ms" => avg_latency_ms.to_f.round,
        "max_latency_ms" => max_latency_ms.to_i,
        "estimated_cost_event_count" => estimated_cost_event_count.to_i,
        "estimated_cost_missing_event_count" => estimated_cost_missing_event_count,
        "prompt_cache_available_input_tokens_total" => prompt_cache_available_input_tokens_total.to_i,
        "provider_round_count" => provider_round_count.to_i,
      }
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
          Arel.sql("SUM(COALESCE(latency_ms, 0))"),
          Arel.sql("SUM(CASE WHEN latency_ms IS NULL THEN 0 ELSE 1 END)"),
          Arel.sql("MAX(COALESCE(latency_ms, 0))"),
          Arel.sql("SUM(CASE WHEN estimated_cost IS NULL THEN 0 ELSE 1 END)"),
        )
        .map do |provider_handle, model_ref, operation_kind, event_count, success_count, failure_count, input_tokens_total, output_tokens_total, cached_input_tokens_total, prompt_cache_available_event_count, prompt_cache_unknown_event_count, prompt_cache_unsupported_event_count, prompt_cache_available_input_tokens_total, estimated_cost_total, total_latency_ms, latency_event_count, max_latency_ms, estimated_cost_event_count|
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

    def tool_breakdown(scope)
      scope
        .joins(:tool_definition)
        .group("tool_definitions.tool_name")
        .order("tool_definitions.tool_name")
        .pluck(
          Arel.sql("tool_definitions.tool_name"),
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN tool_invocations.status IN ('failed', 'canceled') THEN 1 ELSE 0 END)")
        )
        .each_with_object({}) do |(tool_name, count, failures), hash|
          hash[tool_name] = {
            "count" => count.to_i,
            "failures" => failures.to_i,
          }
        end
    end

    def task_delivery_counts(turn)
      resume_attempt_count, retry_attempt_count = AgentTaskRun
        .where(turn_id: turn.id)
        .left_outer_joins(:agent_task_run_detail)
        .pick(
          Arel.sql("SUM(CASE WHEN COALESCE(agent_task_run_details.task_payload, '{}'::jsonb) ->> 'delivery_kind' = 'turn_resume' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN COALESCE(agent_task_run_details.task_payload, '{}'::jsonb) ->> 'delivery_kind' IN ('step_retry', 'paused_retry') THEN 1 ELSE 0 END)")
        )

      {
        "resume_attempt_count" => resume_attempt_count.to_i,
        "retry_attempt_count" => retry_attempt_count.to_i,
      }
    end

    def sum_counts(counts, selected_keys = nil)
      values = if selected_keys.present?
        Array(selected_keys).sum { |key| counts.fetch(key, 0).to_i }
      else
        counts.values.sum(&:to_i)
      end

      values.to_i
    end

    def sum_nested_counts(hash, key)
      hash.values.sum { |payload| payload.fetch(key, 0).to_i }
    end

    def stringify_hash(hash)
      hash.to_h.transform_keys(&:to_s)
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
