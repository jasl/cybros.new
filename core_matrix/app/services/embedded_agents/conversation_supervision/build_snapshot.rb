module EmbeddedAgents
  module ConversationSupervision
    class BuildSnapshot
      CONTEXT_MESSAGE_LIMIT = 8
      ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze
      ACTIVE_SUBAGENT_OBSERVED_STATUSES = %w[running waiting].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
      end

      def call
        @conversation_supervision_session = @conversation_supervision_session.reload
        @conversation = @conversation_supervision_session.target_conversation
        raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if @conversation.blank?

        authority = Authority.call(actor: @actor, conversation_id: @conversation.public_id)
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless authority.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless authority.allowed?

        state = Conversations::UpdateSupervisionState.call(
          conversation: @conversation,
          occurred_at: Time.current
        )
        policy = @conversation.conversation_capability_policy
        bundle_payload = build_bundle_payload(authority:, state:, policy:)

        snapshot = @conversation_supervision_session.conversation_supervision_snapshots.create!(
          installation: @conversation.installation,
          target_conversation: @conversation,
          conversation_supervision_state_public_id: state.public_id,
          conversation_capability_policy_public_id: policy&.public_id,
          anchor_turn_public_id: anchor_turn&.public_id,
          anchor_turn_sequence_snapshot: anchor_turn&.sequence,
          conversation_event_projection_sequence_snapshot: latest_projection_sequence,
          active_workflow_run_public_id: workflow_run&.public_id,
          active_workflow_node_public_id: workflow_node&.public_id,
          active_subagent_session_public_ids: active_subagent_session_public_ids(bundle_payload),
          bundle_payload: bundle_payload,
          machine_status_payload: {}
        )

        machine_status = BuildMachineStatus.call(
          conversation_supervision_snapshot: snapshot,
          conversation_supervision_state: state,
          bundle_payload: bundle_payload
        )
        snapshot.update!(machine_status_payload: machine_status)
        @conversation_supervision_session.update!(last_snapshot_at: snapshot.created_at)
        snapshot.reload
      end

      private

      def build_bundle_payload(authority:, state:, policy:)
        detailed_progress_enabled = authority.detailed_progress_enabled?
        context_view = detailed_progress_enabled ? conversation_context_view : empty_context_view
        turn_feed = detailed_progress_enabled ? ::ConversationSupervision::BuildActivityFeed.call(conversation: @conversation) : []
        runtime_evidence =
          if detailed_progress_enabled && state.overall_state != "idle"
            conversation_runtime_evidence
          else
            {}
          end

        {
          "conversation_context_view" => context_view,
          "runtime_evidence" => runtime_evidence,
          "turn_feed" => turn_feed,
          "activity_feed" => turn_feed,
          "primary_turn_todo_plan_view" => detailed_progress_enabled ? primary_turn_todo_plan_view : nil,
          "active_subagent_turn_todo_plan_views" => detailed_progress_enabled ? active_subagent_turn_todo_plan_views : [],
          "active_subagents" => detailed_progress_enabled ? Array(state.status_payload["active_subagents"]) : [],
          "proof_debug" => proof_debug_payload(
            context_view: context_view,
            turn_feed: turn_feed,
            policy: policy,
            state: state
          ),
          "capability_authority" => {
            "supervision_enabled" => authority.supervision_enabled?,
            "detailed_progress_enabled" => authority.detailed_progress_enabled?,
            "side_chat_enabled" => authority.side_chat_enabled?,
            "control_enabled" => authority.control_enabled?,
            "available_control_verbs" => authority.available_control_verbs,
          },
        }
      end

      def conversation_context_view
        ::ConversationSupervision::BuildContextSnippets.call(
          conversation: @conversation,
          limit: CONTEXT_MESSAGE_LIMIT
        )
      end

      def proof_debug_payload(context_view:, turn_feed:, policy:, state:)
        {
          "conversation_id" => @conversation.public_id,
          "anchor_turn_id" => anchor_turn&.public_id,
          "workflow_run_id" => workflow_run&.public_id,
          "workflow_node_id" => workflow_node&.public_id,
          "conversation_supervision_state_id" => state.public_id,
          "conversation_capability_policy_id" => policy&.public_id,
          "context_message_ids" => context_view.fetch("message_ids"),
          "feed_entry_ids" => turn_feed.map { |entry| entry.fetch("conversation_supervision_feed_entry_id") },
          "feed_event_kinds" => turn_feed.map { |entry| entry.fetch("event_kind") },
          "primary_turn_todo_plan_id" => primary_turn_todo_plan_view&.fetch("turn_todo_plan_id", nil),
          "active_subagent_turn_todo_plan_ids" => active_subagent_turn_todo_plan_views.map { |entry| entry.fetch("turn_todo_plan_id", nil) }.compact,
        }.compact
      end

      def empty_context_view
        {
          "message_ids" => [],
          "turn_ids" => [],
          "context_snippets" => [],
        }
      end

      def conversation_runtime_evidence
        ::ConversationSupervision::BuildRuntimeEvidence.call(
          conversation: @conversation,
          workflow_run: workflow_run
        )
      end

      def active_subagent_session_public_ids(bundle_payload)
        Array(bundle_payload["active_subagent_turn_todo_plan_views"]).filter_map { |entry| entry["subagent_session_id"] }.presence ||
          Array(bundle_payload["active_subagents"]).filter_map { |entry| entry["subagent_session_id"] }
      end

      def primary_turn_todo_plan_view
        return @primary_turn_todo_plan_view if instance_variable_defined?(:@primary_turn_todo_plan_view)

        @primary_turn_todo_plan_view = current_turn_todo_projection.fetch("plan_view")
      end

      def active_subagent_turn_todo_plan_views
        return @active_subagent_turn_todo_plan_views if instance_variable_defined?(:@active_subagent_turn_todo_plan_views)

        @active_subagent_turn_todo_plan_views = active_subagent_sessions.filter_map do |session|
          active_subagent_turn_todo_plan_view_for(session)
        end
      end

      def active_subagent_turn_todo_plan_view_for(session)
        agent_task_run = AgentTaskRun
          .where(conversation: session.conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
          .includes(turn_todo_plan: :turn_todo_plan_items)
          .order(created_at: :desc)
          .first

        view =
          if agent_task_run&.turn_todo_plan.present?
            TurnTodoPlans::BuildView.call(turn_todo_plan: agent_task_run.turn_todo_plan)
          else
            {
              "goal_summary" => agent_task_run&.request_summary || session.request_summary,
              "current_item" => fallback_subagent_current_item(session),
              "items" => [],
              "counts" => {},
            }.compact
          end

        view.merge(
          "subagent_session_id" => session.public_id,
          "profile_key" => session.profile_key,
          "observed_status" => session.observed_status,
          "supervision_state" => session.supervision_state,
        )
      end

      def fallback_subagent_current_item(session)
        return if session.current_focus_summary.blank?

        {
          "title" => session.current_focus_summary,
          "status" => session.supervision_state,
        }
      end

      def current_agent_task_run
        return @current_agent_task_run if instance_variable_defined?(:@current_agent_task_run)

        @current_agent_task_run = AgentTaskRun
          .where(conversation: @conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
          .includes(turn_todo_plan: :turn_todo_plan_items)
          .order(created_at: :desc)
          .first
      end

      def current_turn_todo_projection
        return @current_turn_todo_projection if instance_variable_defined?(:@current_turn_todo_projection)

        @current_turn_todo_projection = ::ConversationSupervision::BuildCurrentTurnTodo.call(
          conversation: @conversation,
          active_agent_task_run: current_agent_task_run,
          workflow_run: workflow_run
        )
      end

      def active_subagent_sessions
        return @active_subagent_sessions if instance_variable_defined?(:@active_subagent_sessions)

        @active_subagent_sessions = @conversation.owned_subagent_sessions
          .close_pending_or_open
          .where(observed_status: ACTIVE_SUBAGENT_OBSERVED_STATUSES)
          .order(:created_at)
          .to_a
      end

      def anchor_turn
        @anchor_turn ||= @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).first ||
          @conversation.turns.order(sequence: :desc).first
      end

      def latest_projection_sequence
        ConversationEvent.where(conversation: @conversation).maximum(:projection_sequence)
      end

      def workflow_run
        @workflow_run ||= @conversation.workflow_runs.order(created_at: :desc).first
      end

      def workflow_node
        @workflow_node ||= begin
          run = workflow_run
          if run.blank?
            nil
          else
            nodes = run.workflow_nodes.order(:ordinal).to_a
            nodes.find { |node| %w[running waiting].include?(node.lifecycle_state) } ||
              nodes.find { |node| %w[queued pending].include?(node.lifecycle_state) } ||
              nodes.last
          end
        end
      end
    end
  end
end
