module AppAPI
  module Conversations
    class TodoPlansController < AppAPI::Conversations::BaseController
      ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze
      ACTIVE_SUBAGENT_OBSERVED_STATUSES = %w[running waiting].freeze

      def show
        ::Conversations::UpdateSupervisionState.call(conversation: @conversation, occurred_at: Time.current)

        render_method_response(
          method_id: "conversation_turn_todo_plan_list",
          conversation_id: @conversation.public_id,
          primary_turn_todo_plan: primary_turn_todo_plan_view,
          active_subagent_turn_todo_plans: active_subagent_turn_todo_plan_views,
        )
      end

      private

      def primary_turn_todo_plan_view
        ConversationSupervision::BuildCurrentTurnTodo.call(conversation: @conversation).fetch("plan_view")
      end

      def active_subagent_turn_todo_plan_views
        @conversation.owned_subagent_connections
          .close_pending_or_open
          .where(observed_status: ACTIVE_SUBAGENT_OBSERVED_STATUSES)
          .order(:created_at)
          .filter_map do |session|
            build_subagent_turn_todo_plan_view(session)
          end
      end

      def build_subagent_turn_todo_plan_view(session)
        agent_task_run = AgentTaskRun
          .where(conversation: session.conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
          .includes(
            turn_todo_plan: [
              :conversation,
              :turn,
              :agent_task_run,
              { turn_todo_plan_items: :delegated_subagent_connection },
            ]
          )
          .order(created_at: :desc)
          .first
        return if agent_task_run&.turn_todo_plan.blank?

        TurnTodoPlans::BuildView.call(turn_todo_plan: agent_task_run.turn_todo_plan).merge(
          "subagent_connection_id" => session.public_id,
          "profile_key" => session.profile_key,
          "observed_status" => session.observed_status,
          "supervision_state" => session.supervision_state,
        )
      end
    end
  end
end
