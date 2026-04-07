module EmbeddedAgents
  module ConversationSupervision
    module Responders
      class BuildPromptPayload
        PLAN_TRANSITION_EVENT_KINDS = %w[
          turn_todo_item_started
          turn_todo_item_completed
          turn_todo_item_blocked
          turn_todo_item_canceled
          turn_todo_item_failed
        ].freeze

        def self.call(...)
          new(...).call
        end

        def initialize(machine_status:)
          @machine_status = machine_status.deep_stringify_keys
        end

        def call
          {
            "overall_state" => @machine_status["overall_state"],
            "last_terminal_state" => @machine_status["last_terminal_state"],
            "last_terminal_at" => @machine_status["last_terminal_at"],
            "board_lane" => @machine_status["board_lane"],
            "board_badges" => @machine_status["board_badges"],
            "request_summary" => @machine_status["request_summary"],
            "current_focus_summary" => idle_snapshot? ? nil : @machine_status["current_focus_summary"],
            "recent_progress_summary" => @machine_status["recent_progress_summary"],
            "waiting_summary" => idle_snapshot? ? nil : @machine_status["waiting_summary"],
            "blocked_summary" => idle_snapshot? ? nil : @machine_status["blocked_summary"],
            "next_step_hint" => idle_snapshot? ? nil : @machine_status["next_step_hint"],
            "primary_turn_todo_plan" => compact_turn_todo_plan(
              @machine_status["primary_turn_todo_plan_view"],
              include_current_item: !idle_snapshot?
            ),
            "active_subagent_turn_todo_plans" => Array(@machine_status["active_subagent_turn_todo_plan_views"]).map do |entry|
              compact_subagent_turn_todo_plan(entry)
            end,
            "recent_plan_transitions" => recent_plan_transitions,
            "context_snippets" => compact_context_snippets,
            "runtime_evidence" => idle_snapshot? ? nil : compact_runtime_evidence,
          }.compact
        end

        private

        def idle_snapshot?
          @machine_status["overall_state"] == "idle"
        end

        def compact_turn_todo_plan(plan_view, include_current_item:)
          return if plan_view.blank?

          compacted = {
            "goal_summary" => plan_view["goal_summary"],
          }
          return compacted.compact unless include_current_item

          compacted.merge(
            "current_item_key" => plan_view["current_item_key"],
            "current_item_title" => plan_view.dig("current_item", "title"),
            "current_item_status" => plan_view.dig("current_item", "status"),
          ).compact
        end

        def compact_subagent_turn_todo_plan(plan_view)
          compact_turn_todo_plan(plan_view, include_current_item: true).to_h.merge(
            "subagent_session_id" => plan_view["subagent_session_id"],
            "profile_key" => plan_view["profile_key"],
            "observed_status" => plan_view["observed_status"],
            "supervision_state" => plan_view["supervision_state"],
          ).compact
        end

        def recent_plan_transitions
          Array(@machine_status["turn_feed"].presence || @machine_status["activity_feed"])
            .select { |entry| PLAN_TRANSITION_EVENT_KINDS.include?(entry["event_kind"]) }
            .last(3)
            .map { |entry| entry.slice("event_kind", "summary", "occurred_at") }
        end

        def compact_context_snippets
          Array(@machine_status.dig("conversation_context", "context_snippets")).last(3).map do |snippet|
            snippet.slice("role", "slot", "excerpt", "keywords")
          end
        end

        def compact_runtime_evidence
          @machine_status.fetch("runtime_evidence", {}).to_h.deep_stringify_keys.slice(
            "workflow_wait_state"
          ).merge(
            "active_command" => compact_runtime_item(@machine_status.dig("runtime_evidence", "active_command")),
            "recent_command" => compact_runtime_item(@machine_status.dig("runtime_evidence", "recent_command")),
            "active_process" => compact_runtime_item(@machine_status.dig("runtime_evidence", "active_process")),
            "recent_process" => compact_runtime_item(@machine_status.dig("runtime_evidence", "recent_process")),
          ).compact
        end

        def compact_runtime_item(item)
          item.to_h.deep_stringify_keys.slice("cwd", "command_preview", "lifecycle_state", "started_at", "ended_at").presence
        end
      end
    end
  end
end
