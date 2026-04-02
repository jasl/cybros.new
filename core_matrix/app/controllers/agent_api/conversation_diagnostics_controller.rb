module AgentAPI
  class ConversationDiagnosticsController < BaseController
    def show
      conversation = find_conversation!(params.fetch(:conversation_id))
      snapshot = ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)

      render json: {
        method_id: "conversation_diagnostics_show",
        conversation_id: conversation.public_id,
        snapshot: serialize_conversation_diagnostics_snapshot(snapshot),
      }
    end

    def turns
      conversation = find_conversation!(params.fetch(:conversation_id))
      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
      snapshots = TurnDiagnosticsSnapshot
        .where(conversation: conversation)
        .joins(:turn)
        .order("turns.sequence ASC")

      render json: {
        method_id: "conversation_diagnostics_turns",
        conversation_id: conversation.public_id,
        items: snapshots.map { |snapshot| serialize_turn_diagnostics_snapshot(snapshot) },
      }
    end

    private

    def serialize_conversation_diagnostics_snapshot(snapshot)
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
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "attributed_user_id" => attributed_user&.public_id,
        "attributed_user_usage_event_count" => snapshot.attributed_user_usage_event_count,
        "attributed_user_input_tokens_total" => snapshot.attributed_user_input_tokens_total,
        "attributed_user_output_tokens_total" => snapshot.attributed_user_output_tokens_total,
        "attributed_user_total_tokens_total" => snapshot.attributed_user_input_tokens_total + snapshot.attributed_user_output_tokens_total,
        "attributed_user_estimated_cost_total" => snapshot.attributed_user_estimated_cost_total.to_s("F"),
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

    def serialize_turn_diagnostics_snapshot(snapshot)
      attributed_user = snapshot.conversation.workspace.user

      {
        "conversation_id" => snapshot.conversation.public_id,
        "turn_id" => snapshot.turn.public_id,
        "lifecycle_state" => snapshot.lifecycle_state,
        "usage_event_count" => snapshot.usage_event_count,
        "input_tokens_total" => snapshot.input_tokens_total,
        "output_tokens_total" => snapshot.output_tokens_total,
        "total_tokens_total" => snapshot.input_tokens_total + snapshot.output_tokens_total,
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "attributed_user_id" => attributed_user&.public_id,
        "attributed_user_usage_event_count" => snapshot.attributed_user_usage_event_count,
        "attributed_user_input_tokens_total" => snapshot.attributed_user_input_tokens_total,
        "attributed_user_output_tokens_total" => snapshot.attributed_user_output_tokens_total,
        "attributed_user_total_tokens_total" => snapshot.attributed_user_input_tokens_total + snapshot.attributed_user_output_tokens_total,
        "attributed_user_estimated_cost_total" => snapshot.attributed_user_estimated_cost_total.to_s("F"),
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
        "metadata" => snapshot.metadata,
      }
    end
  end
end
