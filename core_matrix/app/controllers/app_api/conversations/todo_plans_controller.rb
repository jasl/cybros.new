module AppAPI
  module Conversations
    class TodoPlansController < AppAPI::Conversations::BaseController
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
        ConversationSupervision::BuildCurrentTurnTodo.call(
          conversation: @conversation,
          active_agent_task_run: latest_active_task_runs_by_conversation_id.fetch(@conversation.id, nil)
        ).fetch("plan_view")
      end

      def active_subagent_turn_todo_plan_views
        active_subagent_connections
          .filter_map do |session|
            build_subagent_turn_todo_plan_view(session)
          end
      end

      def build_subagent_turn_todo_plan_view(session)
        agent_task_run = latest_active_task_runs_by_conversation_id.fetch(session.conversation_id, nil)
        return if agent_task_run&.turn_todo_plan.blank?

        TurnTodoPlans::BuildView.call(turn_todo_plan: agent_task_run.turn_todo_plan).merge(
          "subagent_connection_id" => session.public_id,
          "profile_key" => session.profile_key,
          "observed_status" => session.observed_status,
          "supervision_state" => session.supervision_state,
        )
      end

      def active_subagent_connections
        @active_subagent_connections ||= @conversation.owned_subagent_connections
          .close_pending_or_open
          .where(observed_status: ACTIVE_SUBAGENT_OBSERVED_STATUSES)
          .order(:created_at)
          .to_a
      end

      def latest_active_task_runs_by_conversation_id
        return @latest_active_task_runs_by_conversation_id if instance_variable_defined?(:@latest_active_task_runs_by_conversation_id)

        @latest_active_task_runs_by_conversation_id = ConversationSupervision::LoadLatestActiveTaskRuns.call(
          conversation_ids: [@conversation.id] + active_subagent_connections.map(&:conversation_id)
        )
      end
    end
  end
end
