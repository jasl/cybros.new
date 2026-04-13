module Conversations
  class ProjectTurnBootstrapState
    def self.call(...)
      new(...).call
    end

    def self.attributes_for(turn:)
      new(turn:).send(:projection_attributes)
    end

    def initialize(turn:)
      @turn = turn
      @conversation = turn.conversation
    end

    def call
      attributes = projection_attributes
      return @conversation.conversation_supervision_state if attributes.blank?

      state = @conversation.conversation_supervision_state ||
        @conversation.build_conversation_supervision_state(
          installation_id: @conversation.installation_id,
          user_id: @conversation.user_id,
          workspace_id: @conversation.workspace_id,
          agent_id: @conversation.agent_id
        )
      previous_attributes = state.new_record? ? {} : comparable_attributes(state)
      next_attributes = attributes.deep_stringify_keys
      changed = state.new_record? || previous_attributes != next_attributes

      if changed
        ApplicationRecord.transaction do
          state.assign_attributes(
            next_attributes.merge(
              "projection_version" => state.projection_version.to_i + 1
            )
          )
          state.save!
          ConversationSupervision::PublishUpdate.call(
            conversation_supervision_state: state,
            previous_attributes: previous_attributes
          )
        end
      end

      state
    end

    private

    def projection_attributes
      case @turn.workflow_bootstrap_state
      when "pending", "materializing"
        base_projection_attributes.merge(
          overall_state: "queued",
          board_lane: "queued",
          request_summary: request_summary,
          last_progress_at: @turn.workflow_bootstrap_requested_at || @turn.created_at || Time.current,
        )
      when "failed"
        base_projection_attributes.merge(
          overall_state: "failed",
          board_lane: "failed",
          request_summary: request_summary,
          recent_progress_summary: @turn.workflow_bootstrap_failure_payload["error_message"].presence || "Workflow bootstrap failed.",
          last_progress_at: @turn.workflow_bootstrap_finished_at || @turn.workflow_bootstrap_started_at || @turn.workflow_bootstrap_requested_at || Time.current,
        )
      end
    end

    def base_projection_attributes
      {
        installation_id: @conversation.installation_id,
        user_id: @conversation.user_id,
        workspace_id: @conversation.workspace_id,
        agent_id: @conversation.agent_id,
        target_conversation: @conversation,
        last_terminal_state: nil,
        last_terminal_at: nil,
        current_owner_kind: "turn",
        current_owner_public_id: @turn.public_id,
        current_focus_summary: nil,
        waiting_summary: nil,
        blocked_summary: nil,
        next_step_hint: nil,
        retry_due_at: nil,
        active_plan_item_count: 0,
        completed_plan_item_count: 0,
        active_subagent_count: 0,
        board_badges: [],
        status_payload: {
          "turn_bootstrap_state" => @turn.workflow_bootstrap_state,
        },
      }
    end

    def request_summary
      @request_summary ||= ConversationSupervision::BuildGoalSummary.call(
        content: @turn.selected_input_message&.content
      )
    end

    def comparable_attributes(state)
      {
        "overall_state" => state.overall_state,
        "last_terminal_state" => state.last_terminal_state,
        "last_terminal_at" => state.last_terminal_at,
        "current_owner_kind" => state.current_owner_kind,
        "current_owner_public_id" => state.current_owner_public_id,
        "request_summary" => state.request_summary,
        "current_focus_summary" => state.current_focus_summary,
        "recent_progress_summary" => state.recent_progress_summary,
        "waiting_summary" => state.waiting_summary,
        "blocked_summary" => state.blocked_summary,
        "next_step_hint" => state.next_step_hint,
        "last_progress_at" => state.last_progress_at,
        "board_lane" => state.board_lane,
        "lane_changed_at" => state.lane_changed_at,
        "retry_due_at" => state.retry_due_at,
        "active_plan_item_count" => state.active_plan_item_count,
        "completed_plan_item_count" => state.completed_plan_item_count,
        "active_subagent_count" => state.active_subagent_count,
        "board_badges" => state.board_badges,
        "status_payload" => state.status_payload,
      }
    end
  end
end
