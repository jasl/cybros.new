module EmbeddedAgents
  module ConversationSupervision
    class BuildMachineStatus
      def self.call(...)
        new(...).call
      end

      def initialize(conversation_supervision_snapshot:, conversation_supervision_state:, bundle_payload:)
        @conversation_supervision_snapshot = conversation_supervision_snapshot
        @conversation_supervision_state = conversation_supervision_state
        @bundle_payload = bundle_payload
      end

      def call
        {
          "supervision_session_id" => @conversation_supervision_snapshot.conversation_supervision_session.public_id,
          "supervision_snapshot_id" => @conversation_supervision_snapshot.public_id,
          "conversation_id" => @conversation_supervision_snapshot.target_conversation.public_id,
          "overall_state" => @conversation_supervision_state.overall_state,
          "last_terminal_state" => @conversation_supervision_state.last_terminal_state,
          "last_terminal_at" => @conversation_supervision_state.last_terminal_at&.iso8601(6),
          "board_lane" => @conversation_supervision_state.board_lane,
          "board_badges" => @conversation_supervision_state.board_badges,
          "current_owner_kind" => @conversation_supervision_state.current_owner_kind,
          "current_owner_public_id" => @conversation_supervision_state.current_owner_public_id,
          "request_summary" => @conversation_supervision_state.request_summary,
          "current_focus_summary" => @conversation_supervision_state.current_focus_summary,
          "recent_progress_summary" => @conversation_supervision_state.recent_progress_summary,
          "waiting_summary" => @conversation_supervision_state.waiting_summary,
          "blocked_summary" => @conversation_supervision_state.blocked_summary,
          "next_step_hint" => @conversation_supervision_state.next_step_hint,
          "last_progress_at" => @conversation_supervision_state.last_progress_at&.iso8601(6),
          "primary_turn_todo_plan_view" => @bundle_payload["primary_turn_todo_plan_view"],
          "active_subagent_turn_todo_plan_views" => @bundle_payload.fetch("active_subagent_turn_todo_plan_views"),
          "active_subagents" => @bundle_payload.fetch("active_subagents"),
          "turn_feed" => @bundle_payload.fetch("turn_feed"),
          "activity_feed" => @bundle_payload.fetch("activity_feed"),
          "conversation_context" => @bundle_payload.fetch("conversation_context_view"),
          "control" => @bundle_payload.fetch("capability_authority"),
          "proof_debug" => @bundle_payload.fetch("proof_debug"),
        }.compact
      end
    end
  end
end
