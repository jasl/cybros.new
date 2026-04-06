module AppAPI
  class ConversationDiagnosticsController < BaseController
    def show
      conversation = find_conversation!(params.fetch(:conversation_id))
      snapshot = ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
      available_prompt_cache_input_tokens_total = UsageEvent.where(
        conversation_id: conversation.id,
        prompt_cache_status: "available"
      ).sum(:input_tokens)

      render json: {
        method_id: "conversation_diagnostics_show",
        conversation_id: conversation.public_id,
        snapshot: serialize_conversation_diagnostics_snapshot(
          snapshot,
          available_prompt_cache_input_tokens_total: available_prompt_cache_input_tokens_total
        ),
      }
    end

    def turns
      conversation = find_conversation!(params.fetch(:conversation_id))
      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
      snapshots = TurnDiagnosticsSnapshot
        .where(conversation: conversation)
        .joins(:turn)
        .order("turns.sequence ASC")
      available_prompt_cache_input_tokens_by_turn = UsageEvent
        .where(turn_id: snapshots.map(&:turn_id), prompt_cache_status: "available")
        .group(:turn_id)
        .sum(:input_tokens)

      render json: {
        method_id: "conversation_diagnostics_turns",
        conversation_id: conversation.public_id,
        items: snapshots.map do |snapshot|
          serialize_turn_diagnostics_snapshot(
            snapshot,
            available_prompt_cache_input_tokens_total: available_prompt_cache_input_tokens_by_turn.fetch(snapshot.turn_id, 0)
          )
        end,
      }
    end

    private

    def serialize_conversation_diagnostics_snapshot(snapshot, available_prompt_cache_input_tokens_total:)
      attributed_user = snapshot.conversation.workspace.user

      {
        "conversation_id" => snapshot.conversation.public_id,
        "lifecycle_state" => snapshot.lifecycle_state,
        "turn_count" => snapshot.turn_count,
        "active_turn_count" => snapshot.active_turn_count,
        "completed_turn_count" => snapshot.completed_turn_count,
        "failed_turn_count" => snapshot.failed_turn_count,
        "canceled_turn_count" => snapshot.canceled_turn_count,
        "usage_event_count" => snapshot.usage_event_count,
        "input_tokens_total" => snapshot.input_tokens_total,
        "output_tokens_total" => snapshot.output_tokens_total,
        "total_tokens_total" => snapshot.input_tokens_total + snapshot.output_tokens_total,
        "cached_input_tokens_total" => snapshot.cached_input_tokens_total,
        "prompt_cache_available_event_count" => snapshot.prompt_cache_available_event_count,
        "prompt_cache_unknown_event_count" => snapshot.prompt_cache_unknown_event_count,
        "prompt_cache_unsupported_event_count" => snapshot.prompt_cache_unsupported_event_count,
        "prompt_cache_hit_rate" => prompt_cache_hit_rate(
          cached_input_tokens_total: snapshot.cached_input_tokens_total,
          available_event_count: snapshot.prompt_cache_available_event_count,
          available_input_tokens_total: available_prompt_cache_input_tokens_total
        ),
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "estimated_cost_event_count" => snapshot.estimated_cost_event_count,
        "estimated_cost_missing_event_count" => snapshot.estimated_cost_missing_event_count,
        "cost_data_available" => snapshot.estimated_cost_event_count.positive?,
        "cost_data_complete" => (snapshot.estimated_cost_event_count + snapshot.estimated_cost_missing_event_count).positive? && snapshot.estimated_cost_missing_event_count.zero?,
        "attributed_user_id" => attributed_user&.public_id,
        "attributed_user_usage_event_count" => snapshot.attributed_user_usage_event_count,
        "attributed_user_input_tokens_total" => snapshot.attributed_user_input_tokens_total,
        "attributed_user_output_tokens_total" => snapshot.attributed_user_output_tokens_total,
        "attributed_user_total_tokens_total" => snapshot.attributed_user_input_tokens_total + snapshot.attributed_user_output_tokens_total,
        "attributed_user_estimated_cost_total" => snapshot.attributed_user_estimated_cost_total.to_s("F"),
        "attributed_user_estimated_cost_event_count" => snapshot.attributed_user_estimated_cost_event_count,
        "attributed_user_estimated_cost_missing_event_count" => snapshot.attributed_user_estimated_cost_missing_event_count,
        "attributed_user_cost_data_available" => snapshot.attributed_user_estimated_cost_event_count.positive?,
        "attributed_user_cost_data_complete" => (snapshot.attributed_user_estimated_cost_event_count + snapshot.attributed_user_estimated_cost_missing_event_count).positive? && snapshot.attributed_user_estimated_cost_missing_event_count.zero?,
        "provider_round_count" => snapshot.provider_round_count,
        "tool_call_count" => snapshot.tool_call_count,
        "tool_failure_count" => snapshot.tool_failure_count,
        "command_run_count" => snapshot.command_run_count,
        "command_failure_count" => snapshot.command_failure_count,
        "process_run_count" => snapshot.process_run_count,
        "process_failure_count" => snapshot.process_failure_count,
        "subagent_session_count" => snapshot.subagent_session_count,
        "input_variant_count" => snapshot.input_variant_count,
        "output_variant_count" => snapshot.output_variant_count,
        "steer_count" => [snapshot.input_variant_count - snapshot.turn_count, 0].max,
        "resume_attempt_count" => snapshot.resume_attempt_count,
        "retry_attempt_count" => snapshot.retry_attempt_count,
        "most_expensive_turn_id" => snapshot.most_expensive_turn&.public_id,
        "most_rounds_turn_id" => snapshot.most_rounds_turn&.public_id,
        "metadata" => snapshot.metadata,
      }
    end

    def serialize_turn_diagnostics_snapshot(snapshot, available_prompt_cache_input_tokens_total:)
      attributed_user = snapshot.conversation.workspace.user

      {
        "conversation_id" => snapshot.conversation.public_id,
        "turn_id" => snapshot.turn.public_id,
        "lifecycle_state" => snapshot.lifecycle_state,
        "usage_event_count" => snapshot.usage_event_count,
        "input_tokens_total" => snapshot.input_tokens_total,
        "output_tokens_total" => snapshot.output_tokens_total,
        "total_tokens_total" => snapshot.input_tokens_total + snapshot.output_tokens_total,
        "cached_input_tokens_total" => snapshot.cached_input_tokens_total,
        "prompt_cache_available_event_count" => snapshot.prompt_cache_available_event_count,
        "prompt_cache_unknown_event_count" => snapshot.prompt_cache_unknown_event_count,
        "prompt_cache_unsupported_event_count" => snapshot.prompt_cache_unsupported_event_count,
        "prompt_cache_hit_rate" => prompt_cache_hit_rate(
          cached_input_tokens_total: snapshot.cached_input_tokens_total,
          available_event_count: snapshot.prompt_cache_available_event_count,
          available_input_tokens_total: available_prompt_cache_input_tokens_total
        ),
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "estimated_cost_event_count" => snapshot.estimated_cost_event_count,
        "estimated_cost_missing_event_count" => snapshot.estimated_cost_missing_event_count,
        "cost_data_available" => snapshot.estimated_cost_event_count.positive?,
        "cost_data_complete" => (snapshot.estimated_cost_event_count + snapshot.estimated_cost_missing_event_count).positive? && snapshot.estimated_cost_missing_event_count.zero?,
        "attributed_user_id" => attributed_user&.public_id,
        "attributed_user_usage_event_count" => snapshot.attributed_user_usage_event_count,
        "attributed_user_input_tokens_total" => snapshot.attributed_user_input_tokens_total,
        "attributed_user_output_tokens_total" => snapshot.attributed_user_output_tokens_total,
        "attributed_user_total_tokens_total" => snapshot.attributed_user_input_tokens_total + snapshot.attributed_user_output_tokens_total,
        "attributed_user_estimated_cost_total" => snapshot.attributed_user_estimated_cost_total.to_s("F"),
        "attributed_user_estimated_cost_event_count" => snapshot.attributed_user_estimated_cost_event_count,
        "attributed_user_estimated_cost_missing_event_count" => snapshot.attributed_user_estimated_cost_missing_event_count,
        "attributed_user_cost_data_available" => snapshot.attributed_user_estimated_cost_event_count.positive?,
        "attributed_user_cost_data_complete" => (snapshot.attributed_user_estimated_cost_event_count + snapshot.attributed_user_estimated_cost_missing_event_count).positive? && snapshot.attributed_user_estimated_cost_missing_event_count.zero?,
        "avg_latency_ms" => snapshot.avg_latency_ms,
        "max_latency_ms" => snapshot.max_latency_ms,
        "provider_round_count" => snapshot.provider_round_count,
        "tool_call_count" => snapshot.tool_call_count,
        "tool_failure_count" => snapshot.tool_failure_count,
        "command_run_count" => snapshot.command_run_count,
        "command_failure_count" => snapshot.command_failure_count,
        "process_run_count" => snapshot.process_run_count,
        "process_failure_count" => snapshot.process_failure_count,
        "subagent_session_count" => snapshot.subagent_session_count,
        "input_variant_count" => snapshot.input_variant_count,
        "output_variant_count" => snapshot.output_variant_count,
        "steer_count" => [snapshot.input_variant_count - 1, 0].max,
        "resume_attempt_count" => snapshot.resume_attempt_count,
        "retry_attempt_count" => snapshot.retry_attempt_count,
        "pause_state" => snapshot.pause_state,
        "metadata" => snapshot.metadata,
      }
    end

    def prompt_cache_hit_rate(cached_input_tokens_total:, available_event_count:, available_input_tokens_total:)
      return nil if available_event_count.to_i.zero?
      return nil if available_input_tokens_total.to_i.zero?

      cached_input_tokens_total.to_f / available_input_tokens_total.to_f
    end
  end
end
