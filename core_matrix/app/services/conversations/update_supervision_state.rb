module Conversations
  class UpdateSupervisionState
    TERMINAL_TASK_LIFECYCLE_STATES = %w[completed failed interrupted canceled].freeze
    ACTIVE_SUBAGENT_OBSERVED_STATUSES = %w[running waiting].freeze
    TODO_PLAN_INCLUDES = ConversationSupervision::LoadLatestActiveTaskRuns::TODO_PLAN_INCLUDES

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current, include_runtime_evidence: true)
      @conversation = conversation
      @occurred_at = occurred_at
      @include_runtime_evidence = include_runtime_evidence
    end

    def call
      state = @conversation.conversation_supervision_state ||
        @conversation.build_conversation_supervision_state(
          installation_id: @conversation.installation_id,
          user_id: @conversation.user_id,
          workspace_id: @conversation.workspace_id,
          agent_id: @conversation.agent_id
        )
      previous_attributes = state.new_record? ? {} : comparable_attributes(state)
      next_attributes = projection_attributes(state:).deep_stringify_keys
      changed = state.new_record? || previous_attributes != next_attributes

      if changed
        ApplicationRecord.transaction do
          state.assign_attributes(
            next_attributes.merge(
              "projection_version" => state.projection_version.to_i + 1
            )
          )
          state.save!

          changeset = semantic_changeset(previous_attributes:, current_attributes: next_attributes)
          feed_entries =
            if detailed_progress_enabled?
              ConversationSupervision::AppendFeedEntries.call(
                conversation: @conversation,
                changeset: changeset,
                occurred_at: @occurred_at
              )
            else
              []
            end
          ConversationSupervision::PublishUpdate.call(
            conversation_supervision_state: state,
            previous_attributes: previous_attributes,
            latest_feed_entry: feed_entries.last
          )
        end
      end

      state
    end

    private

    def projection_attributes(state:)
      {
        installation_id: @conversation.installation_id,
        user_id: @conversation.user_id,
        workspace_id: @conversation.workspace_id,
        agent_id: @conversation.agent_id,
        target_conversation: @conversation,
        overall_state: overall_state,
        last_terminal_state: last_terminal_state,
        last_terminal_at: last_terminal_at,
        current_owner_kind: current_owner_kind,
        current_owner_public_id: current_owner_public_id,
        request_summary: request_summary,
        current_focus_summary: current_focus_summary,
        recent_progress_summary: recent_progress_summary,
        waiting_summary: waiting_summary,
        blocked_summary: blocked_summary,
        next_step_hint: next_step_hint,
        last_progress_at: last_progress_at,
        board_lane: board_lane,
        lane_changed_at: lane_changed_at(state),
        retry_due_at: retry_due_at,
        active_plan_item_count: active_plan_item_count,
        completed_plan_item_count: completed_plan_item_count,
        active_subagent_count: active_subagent_count,
        board_badges: board_badges,
      }.tap do |attributes|
        attributes[:status_payload] = status_payload if status_payload.present? || state.conversation_supervision_state_detail.present?
      end
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

    def overall_state
      return turn_bootstrap_projection_attributes.fetch(:overall_state) if turn_bootstrap_projection_attributes.present?
      return "blocked" if workflow_run&.blocked?
      return "waiting" if workflow_run&.waiting?
      return current_task_run.supervision_state if current_task_run.present?
      return active_conversation_subagent_connection.supervision_state if active_conversation_subagent_connection.present?
      return owned_subagent_overall_state if active_owned_subagent_connections.any?
      return "running" if workflow_progressing_without_task?
      return "queued" if active_workflow?

      "idle"
    end

    def last_terminal_state
      return latest_terminal_task_run.lifecycle_state if latest_terminal_task_run.present?
      return workflow_terminal_state if workflow_terminal?

      nil
    end

    def last_terminal_at
      return latest_terminal_task_run.finished_at if latest_terminal_task_run.present?
      return workflow_terminal_at if workflow_terminal?

      nil
    end

    def current_owner_kind
      return turn_bootstrap_projection_attributes.fetch(:current_owner_kind) if turn_bootstrap_projection_attributes.present?
      return "workflow_run" if workflow_run&.waiting? || workflow_run&.blocked?
      return "agent_task_run" if current_task_run.present?
      return "subagent_connection" if active_conversation_subagent_connection.present?
      return "subagent_connection" if active_owned_subagent_connections.first.present?
      return "workflow_run" if active_workflow?

      nil
    end

    def current_owner_public_id
      return turn_bootstrap_projection_attributes.fetch(:current_owner_public_id) if turn_bootstrap_projection_attributes.present?
      return workflow_run.public_id if workflow_run&.waiting? || workflow_run&.blocked?
      return current_task_run.public_id if current_task_run.present?
      return active_conversation_subagent_connection.public_id if active_conversation_subagent_connection.present?
      return active_owned_subagent_connections.first&.public_id if active_owned_subagent_connections.first.present?
      return workflow_run.public_id if active_workflow?

      nil
    end

    def request_summary
      return unless detailed_progress_enabled?
      return turn_bootstrap_projection_attributes[:request_summary] if turn_bootstrap_projection_attributes.present?

      current_task_plan_summary&.fetch("goal_summary", nil) ||
        current_task_run&.request_summary ||
        active_conversation_subagent_connection&.request_summary ||
        active_owned_subagent_turn_plan_summaries.filter_map { |summary| summary["goal_summary"] }.first ||
        active_owned_subagent_connections.filter_map(&:request_summary).first ||
        latest_task_plan_summary&.fetch("goal_summary", nil) ||
        latest_task_run&.request_summary ||
        conversation_goal_summary
    end

    def current_focus_summary
      return unless detailed_progress_enabled?
      return if overall_state == "idle"
      return turn_bootstrap_projection_attributes[:current_focus_summary] if turn_bootstrap_projection_attributes.present?

      current_task_plan_summary&.fetch("current_item_title", nil) ||
        current_task_run&.current_focus_summary ||
        active_conversation_subagent_connection&.current_focus_summary ||
        active_owned_subagent_turn_plan_summaries.filter_map { |summary| summary["current_item_title"] }.first ||
        active_owned_subagent_connections.filter_map(&:current_focus_summary).first ||
        generic_runtime_current_focus_summary ||
        basic_task_run_current_focus_summary
    end

    def recent_progress_summary
      return unless detailed_progress_enabled?
      return turn_bootstrap_projection_attributes[:recent_progress_summary] if turn_bootstrap_projection_attributes.present?

      plan_backed_recent_progress_summary ||
        current_task_run&.recent_progress_summary ||
        current_task_progress_entry_summary ||
        active_conversation_subagent_connection&.recent_progress_summary ||
        active_owned_subagent_connections.filter_map(&:recent_progress_summary).first ||
        latest_progress_entry_summary ||
        terminal_recent_progress_summary ||
        generic_runtime_recent_progress_summary
    end

    def waiting_summary
      return unless detailed_progress_enabled?
      return turn_bootstrap_projection_attributes[:waiting_summary] if turn_bootstrap_projection_attributes.present?

      return humanized_subagent_barrier_summary if workflow_run&.waiting_on_subagent_barrier?
      return active_conversation_subagent_connection&.waiting_summary if active_conversation_subagent_connection&.waiting_summary.present?
      return active_owned_subagent_connections.filter_map(&:waiting_summary).first if workflow_run&.waiting?
      return generic_runtime_waiting_summary if %w[waiting blocked].include?(overall_state)

      nil
    end

    def blocked_summary
      return unless detailed_progress_enabled?
      return turn_bootstrap_projection_attributes[:blocked_summary] if turn_bootstrap_projection_attributes.present?

      return current_task_run&.blocked_summary if current_task_run&.blocked_summary.present?
      return active_conversation_subagent_connection&.blocked_summary if active_conversation_subagent_connection&.blocked_summary.present?
      return active_owned_subagent_connections.filter_map(&:blocked_summary).first if workflow_run&.blocked?
      return workflow_run.wait_last_error_summary if workflow_run&.blocked? && workflow_run.wait_last_error_summary.present?

      nil
    end

    def next_step_hint
      return unless detailed_progress_enabled?
      return turn_bootstrap_projection_attributes[:next_step_hint] if turn_bootstrap_projection_attributes.present?

      current_task_run&.next_step_hint ||
        active_conversation_subagent_connection&.next_step_hint ||
        active_owned_subagent_connections.filter_map(&:next_step_hint).first
    end

    def last_progress_at
      return turn_bootstrap_projection_attributes.fetch(:last_progress_at) if turn_bootstrap_projection_attributes.present?

      [
        current_task_run&.last_progress_at,
        active_conversation_subagent_connection&.last_progress_at,
        active_owned_subagent_connections.filter_map(&:last_progress_at).max,
        workflow_activity_at,
        latest_task_run&.last_progress_at,
        last_terminal_at,
        workflow_run&.waiting_since_at,
        workflow_run&.created_at,
      ].compact.max || @occurred_at
    end

    def board_lane
      return turn_bootstrap_projection_attributes.fetch(:board_lane) if turn_bootstrap_projection_attributes.present?

      @board_lane ||= ConversationSupervision::ClassifyBoardLane.call(
        overall_state: overall_state,
        active_subagent_count: board_lane_active_subagent_count,
        retry_due_at: retry_due_at
      )
    end

    def lane_changed_at(state)
      return @occurred_at if state.new_record?
      return state.lane_changed_at || @occurred_at if state.board_lane == board_lane

      @occurred_at
    end

    def retry_due_at
      workflow_run&.wait_next_retry_at
    end

    def active_plan_item_count
      return turn_bootstrap_projection_attributes.fetch(:active_plan_item_count, 0) if turn_bootstrap_projection_attributes.present?

      current_turn_plan_summary&.fetch("active_item_count", 0).to_i
    end

    def completed_plan_item_count
      return turn_bootstrap_projection_attributes.fetch(:completed_plan_item_count, 0) if turn_bootstrap_projection_attributes.present?

      current_turn_plan_summary&.fetch("completed_item_count", 0).to_i
    end

    def active_subagent_count
      return turn_bootstrap_projection_attributes.fetch(:active_subagent_count, 0) if turn_bootstrap_projection_attributes.present?

      active_owned_subagent_connections.count
    end

    def board_badges
      return turn_bootstrap_projection_attributes.fetch(:board_badges, []) if turn_bootstrap_projection_attributes.present?

      badges = []
      badges << "#{active_plan_item_count} active plan item#{"s" unless active_plan_item_count == 1}" if active_plan_item_count.positive?
      badges << "#{active_subagent_count} child task#{"s" unless active_subagent_count == 1}" if active_subagent_count.positive?
      badges << "retry pending" if retry_due_at.present?
      badges
    end

    def status_payload
      return {} unless detailed_progress_enabled?
      return turn_bootstrap_projection_attributes.fetch(:status_payload, {}) if turn_bootstrap_projection_attributes.present?

      {
        "current_turn_plan_summary" => current_turn_plan_summary,
        "runtime_evidence" => active_runtime_evidence,
        "active_subagent_turn_plan_summaries" => active_owned_subagent_turn_plan_summaries.presence,
        "active_subagents" => active_subagent_payloads.presence,
        "latest_progress_entry" => latest_progress_entry_payload,
      }.compact
    end

    def active_runtime_evidence
      return if turn_bootstrap_projection_attributes.present?
      return if overall_state == "idle"
      return if suppress_runtime_evidence_for_task_run?

      runtime_evidence.presence
    end

    def active_subagent_payloads
      return [] if turn_bootstrap_projection_attributes.present?

      active_owned_subagent_connections.map do |session|
        plan_summary = active_subagent_turn_plan_summary_for(session)
        {
          "subagent_connection_id" => session.public_id,
          "observed_status" => session.observed_status,
          "supervision_state" => session.supervision_state,
          "profile_key" => session.profile_key,
          "request_summary" => plan_summary&.fetch("goal_summary", nil) || session.request_summary,
          "current_focus_summary" => plan_summary&.fetch("current_item_title", nil) || session.current_focus_summary,
          "waiting_summary" => session.waiting_summary,
          "blocked_summary" => session.blocked_summary,
          "next_step_hint" => session.next_step_hint,
          "turn_todo_plan_summary" => plan_summary,
        }.compact
      end
    end

    def latest_progress_entry_payload
      return if turn_bootstrap_projection_attributes.present?
      return if latest_progress_entry.blank?

      {
        "agent_task_run_id" => latest_progress_entry.agent_task_run.public_id,
        "sequence" => latest_progress_entry.sequence,
        "entry_kind" => latest_progress_entry.entry_kind,
        "summary" => latest_progress_entry.summary,
        "occurred_at" => latest_progress_entry.occurred_at.iso8601,
      }.compact
    end

    def humanized_subagent_barrier_summary
      sessions = barrier_aware_subagent_connections
      count = sessions.size
      return "Waiting for child work to finish." if count.zero?

      summary = "Waiting for #{count} child #{"task".pluralize(count)} to finish"
      focuses = sessions.filter_map(&:current_focus_summary).first(2)
      return "#{summary}." if focuses.empty?

      "#{summary}: #{focuses.join(", ")}."
    end

    def conversation_goal_summary
      @conversation_goal_summary ||= begin
        turn = @conversation.feed_anchor_turn ||
          @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).first ||
          @conversation.turns.order(sequence: :desc).first
        content = turn&.selected_input_message&.content.to_s
        ConversationSupervision::BuildGoalSummary.call(content: content)
      end
    end

    def recent_plan_transition_summary
      recent_plan_transition_entry&.summary
    end

    def plan_backed_recent_progress_summary
      return unless plan_backed_progress?

      recent_plan_transition_summary
    end

    def recent_plan_transition_entry
      return @recent_plan_transition_entry if instance_variable_defined?(:@recent_plan_transition_entry)

      @recent_plan_transition_entry = ConversationSupervisionFeedEntry
        .where(target_conversation: @conversation)
        .where(event_kind: plan_transition_event_kinds)
        .order(sequence: :desc)
        .first
    end

    def plan_transition_event_kinds
      %w[
        turn_todo_item_started
        turn_todo_item_completed
        turn_todo_item_blocked
        turn_todo_item_canceled
        turn_todo_item_failed
      ]
    end

    def runtime_evidence
      return @runtime_evidence if instance_variable_defined?(:@runtime_evidence)
      return @runtime_evidence = {} unless @include_runtime_evidence

      @runtime_evidence = ConversationSupervision::BuildRuntimeEvidence.call(
        conversation: @conversation,
        workflow_run: workflow_run
      )
    end

    def generic_runtime_current_focus_summary
      return if suppress_runtime_evidence_for_task_run? && !basic_task_run_fallback?
      return summarize_active_process(runtime_evidence["active_process"]) if runtime_evidence["active_process"].present?
      return summarize_active_command(runtime_evidence["active_command"]) if runtime_evidence["active_command"].present?
      return "Working through the current turn" if workflow_progressing_without_task?
      return "Waiting on the current workflow step" if workflow_run&.waiting?
      return "Resolving the blocked workflow step" if workflow_run&.blocked?

      nil
    end

    def generic_runtime_recent_progress_summary
      return if suppress_runtime_evidence_for_task_run?
      return summarize_terminal_process(runtime_evidence["recent_process"]) if runtime_evidence["recent_process"].present?
      return summarize_terminal_command(runtime_evidence["recent_command"]) if runtime_evidence["recent_command"].present?

      nil
    end

    def terminal_recent_progress_summary
      return unless overall_state == "idle"
      return if last_terminal_state.blank?

      case last_terminal_state
      when "completed" then "The turn completed."
      when "failed" then "The turn failed."
      when "interrupted" then "The turn was interrupted."
      end
    end

    def generic_runtime_waiting_summary
      return "Waiting for a running process#{location_phrase(runtime_evidence["active_process"])} to finish." if runtime_evidence["active_process"].present?
      return "Waiting for a running shell command#{location_phrase(runtime_evidence["active_command"])} to finish." if runtime_evidence["active_command"].present?
      return "Waiting for the current workflow step to unblock." if workflow_run&.waiting?
      return "Waiting for the blocked workflow step to clear." if workflow_run&.blocked?

      nil
    end

    def summarize_active_command(command)
      "Monitoring a running shell command#{location_phrase(command)}"
    end

    def summarize_terminal_command(command)
      case command["lifecycle_state"]
      when "failed"
        "A shell command failed#{location_phrase(command)}."
      when "canceled", "interrupted"
        "A shell command was interrupted#{location_phrase(command)}."
      else
        "A shell command finished#{location_phrase(command)}."
      end
    end

    def summarize_active_process(process)
      "Monitoring a running process#{location_phrase(process)}"
    end

    def summarize_terminal_process(process)
      case process["lifecycle_state"]
      when "failed", "lost"
        "A process failed#{location_phrase(process)}."
      when "stopped"
        "A process stopped#{location_phrase(process)}."
      else
        "A process finished#{location_phrase(process)}."
      end
    end

    def location_phrase(payload)
      cwd = payload.to_h["cwd"].presence
      return "" if cwd.blank?

      " in #{cwd}"
    end

    def workflow_run
      return @workflow_run if instance_variable_defined?(:@workflow_run)

      @workflow_run = if @conversation.latest_active_workflow_run&.active?
        @conversation.latest_active_workflow_run
      else
        @conversation.workflow_runs.order(created_at: :desc).first
      end
    end

    def current_task_run
      return @current_task_run if instance_variable_defined?(:@current_task_run)

      @current_task_run = latest_active_task_runs_by_conversation_id.fetch(@conversation.id, nil)
    end

    def latest_task_run
      return @latest_task_run if instance_variable_defined?(:@latest_task_run)

      @latest_task_run = current_task_run ||
        AgentTaskRun
          .includes(:agent_task_progress_entries, turn_todo_plan: TODO_PLAN_INCLUDES)
          .where(conversation: @conversation)
          .order(created_at: :desc)
          .first
    end

    def latest_terminal_task_run
      return @latest_terminal_task_run if instance_variable_defined?(:@latest_terminal_task_run)

      @latest_terminal_task_run = AgentTaskRun
        .where(conversation: @conversation, lifecycle_state: TERMINAL_TASK_LIFECYCLE_STATES)
        .where.not(finished_at: nil)
        .order(finished_at: :desc, created_at: :desc)
        .first
    end

    def latest_progress_entry
      return @latest_progress_entry if instance_variable_defined?(:@latest_progress_entry)

      @latest_progress_entry =
        if latest_task_run.blank?
          nil
        elsif latest_task_run == current_task_run
          current_task_progress_entry
        else
          latest_task_run.agent_task_progress_entries.order(sequence: :desc).first
        end
    end

    def current_task_progress_entry
      return @current_task_progress_entry if instance_variable_defined?(:@current_task_progress_entry)

      @current_task_progress_entry = current_task_progress_entries.first
    end

    def current_task_progress_entry_summary
      return if basic_task_run_fallback?

      current_task_progress_entry&.summary
    end

    def latest_progress_entry_summary
      return if basic_task_run_fallback?

      latest_progress_entry&.summary
    end

    def conversation_subagent_connection
      return @conversation_subagent_connection if instance_variable_defined?(:@conversation_subagent_connection)

      @conversation_subagent_connection = @conversation.subagent_connection
    end

    def active_conversation_subagent_connection
      session = conversation_subagent_connection
      return unless active_subagent_connection?(session)

      session
    end

    def active_owned_subagent_connections
      @active_owned_subagent_connections ||= @conversation.owned_subagent_connections
        .close_pending_or_open
        .where(observed_status: ACTIVE_SUBAGENT_OBSERVED_STATUSES)
        .order(:created_at)
        .to_a
    end

    def current_task_progress_entries
      return @current_task_progress_entries if instance_variable_defined?(:@current_task_progress_entries)

      @current_task_progress_entries =
        if current_task_run.present?
          current_task_run.agent_task_progress_entries.sort_by { |entry| -entry.sequence }
        else
          []
        end
    end

    def barrier_subagent_connections
      return [] unless workflow_run&.waiting_on_subagent_barrier?

      workflow_run.subagent_barrier_sessions.select { |session| active_subagent_connection?(session) }
    end

    def barrier_aware_subagent_connections
      sessions = barrier_subagent_connections
      return sessions if sessions.present?

      active_owned_subagent_connections
    end

    def current_task_plan
      current_task_run&.turn_todo_plan
    end

    def current_task_plan_view
      return @current_task_plan_view if instance_variable_defined?(:@current_task_plan_view)

      @current_task_plan_view =
        if current_task_plan.present?
          TurnTodoPlans::BuildView.call(turn_todo_plan: current_task_plan)
        end
    end

    def current_task_plan_summary
      return @current_task_plan_summary if instance_variable_defined?(:@current_task_plan_summary)

      @current_task_plan_summary =
        if current_task_plan.present?
          TurnTodoPlans::BuildCompactView.call(turn_todo_plan: current_task_plan)
        end
    end

    def current_turn_plan_summary
      current_task_plan_summary
    end

    def latest_task_plan_summary
      return @latest_task_plan_summary if instance_variable_defined?(:@latest_task_plan_summary)

      @latest_task_plan_summary =
        if latest_task_run&.turn_todo_plan.present?
          TurnTodoPlans::BuildCompactView.call(turn_todo_plan: latest_task_run.turn_todo_plan)
        end
    end

    def active_owned_subagent_turn_plan_summaries
      return @active_owned_subagent_turn_plan_summaries if instance_variable_defined?(:@active_owned_subagent_turn_plan_summaries)

      @active_owned_subagent_turn_plan_summaries = active_owned_subagent_connections.filter_map do |session|
        active_subagent_turn_plan_summary_for(session)
      end
    end

    def active_subagent_turn_plan_summary_for(session)
      active_subagent_turn_plan_summaries_by_session_id.fetch(session.id, nil)
    end

    def active_subagent_turn_plan_summaries_by_session_id
      return @active_subagent_turn_plan_summaries_by_session_id if instance_variable_defined?(:@active_subagent_turn_plan_summaries_by_session_id)

      @active_subagent_turn_plan_summaries_by_session_id = active_owned_subagent_connections.each_with_object({}) do |session, summaries|
        agent_task_run = latest_active_task_runs_by_conversation_id.fetch(session.conversation_id, nil)
        next if agent_task_run&.turn_todo_plan.blank?

        summaries[session.id] = TurnTodoPlans::BuildCompactView.call(turn_todo_plan: agent_task_run.turn_todo_plan).merge(
          "subagent_connection_id" => session.public_id,
          "profile_key" => session.profile_key,
          "observed_status" => session.observed_status,
          "supervision_state" => session.supervision_state,
        )
      end
    end

    def latest_active_task_runs_by_conversation_id
      return @latest_active_task_runs_by_conversation_id if instance_variable_defined?(:@latest_active_task_runs_by_conversation_id)

      @latest_active_task_runs_by_conversation_id = ConversationSupervision::LoadLatestActiveTaskRuns.call(
        conversation_ids: [@conversation.id] + active_owned_subagent_connections.map(&:conversation_id),
        include_progress_entries: true
      )
    end

    def active_subagent_connection?(session)
      session.present? &&
        session.close_pending_or_open? &&
        ACTIVE_SUBAGENT_OBSERVED_STATUSES.include?(session.observed_status)
    end

    def owned_subagent_overall_state
      states = active_owned_subagent_connections.map(&:supervision_state)
      return "blocked" if states.include?("blocked")
      return "waiting" if states.include?("waiting")

      "running"
    end

    def board_lane_active_subagent_count
      return 0 if turn_bootstrap_projection_attributes.present?
      return barrier_aware_subagent_connections.count if workflow_run&.waiting_on_subagent_barrier?

      active_subagent_count
    end

    def workflow_terminal?
      workflow_run.present? && %w[completed failed canceled].include?(workflow_run.lifecycle_state)
    end

    def active_workflow?
      workflow_run&.active?
    end

    def workflow_progressing_without_task?
      active_workflow? && running_workflow_node.present?
    end

    def turn_bootstrap_projection_attributes
      return @turn_bootstrap_projection_attributes if instance_variable_defined?(:@turn_bootstrap_projection_attributes)

      @turn_bootstrap_projection_attributes = begin
        turn = latest_turn_pending_bootstrap
        if turn.present?
          Conversations::ProjectTurnBootstrapState.attributes_for(turn: turn)
        end
      end
    end

    def latest_turn_pending_bootstrap
      return nil if current_task_run.present?
      return nil if active_conversation_subagent_connection.present?
      return nil if active_owned_subagent_connections.any?

      turn = @conversation.latest_active_turn || @conversation.latest_turn
      return nil if turn.blank?
      return turn if turn.workflow_bootstrap_failed? && turn.workflow_run.present?

      return nil if active_workflow? || workflow_run&.waiting? || workflow_run&.blocked?
      return nil unless %w[pending materializing failed].include?(turn.workflow_bootstrap_state)

      turn
    end

    def basic_task_run_current_focus_summary
      return unless basic_task_run_fallback?
      return unless overall_state == "running"

      "Working through the current turn"
    end

    def basic_task_run_fallback?
      return @basic_task_run_fallback if instance_variable_defined?(:@basic_task_run_fallback)

      @basic_task_run_fallback =
        current_task_run.present? &&
        current_task_plan.blank? &&
        current_task_run.current_focus_summary.blank? &&
        current_task_run.recent_progress_summary.blank? &&
        current_task_run.waiting_summary.blank? &&
        current_task_run.blocked_summary.blank? &&
        current_task_run.next_step_hint.blank?
    end

    def suppress_runtime_evidence_for_task_run?
      current_task_run.present? && !%w[waiting blocked].include?(overall_state)
    end

    def plan_backed_progress?
      current_task_plan.present? || latest_task_plan_summary.present?
    end

    def workflow_terminal_state
      case workflow_run.lifecycle_state
      when "completed" then "completed"
      when "failed" then "failed"
      when "canceled" then "interrupted"
      end
    end

    def workflow_terminal_at
      workflow_run.updated_at
    end

    def workflow_activity_at
      latest_workflow_activity_node&.updated_at || workflow_run&.updated_at
    end

    def latest_workflow_activity_node
      return @latest_workflow_activity_node if instance_variable_defined?(:@latest_workflow_activity_node)

      @latest_workflow_activity_node = begin
        run = workflow_run
        if run.present?
          run.workflow_nodes
            .where.not(lifecycle_state: %w[pending queued])
            .order(updated_at: :desc, ordinal: :desc)
            .first
        end
      end
    end

    def running_workflow_node
      return @running_workflow_node if instance_variable_defined?(:@running_workflow_node)

      @running_workflow_node = begin
        run = workflow_run
        if run.present?
          run.workflow_nodes
            .where(lifecycle_state: "running")
            .order(updated_at: :desc, ordinal: :desc)
            .first
        end
      end
    end

    def semantic_changeset(previous_attributes:, current_attributes:)
      return [] unless detailed_progress_enabled?

      previous = previous_attributes.deep_stringify_keys
      current = current_attributes.deep_stringify_keys
      changes = []

      if previous.blank? && current["overall_state"] != "idle"
        changes << semantic_change(
          event_kind: "turn_started",
          summary: current["request_summary"].presence || "Started the turn.",
          current_attributes: current
        )
      end

      if current["overall_state"] == "waiting" && previous["overall_state"] != "waiting"
        changes << semantic_change(
          event_kind: "waiting_started",
          summary: current["waiting_summary"].presence || "Waiting on follow-up work.",
          current_attributes: current
        )
      elsif previous["overall_state"] == "waiting" && current["overall_state"] != "waiting"
        changes << semantic_change(
          event_kind: "waiting_cleared",
          summary: "Cleared the waiting state.",
          current_attributes: current
        )
      end

      if current["overall_state"] == "blocked" && previous["overall_state"] != "blocked"
        changes << semantic_change(
          event_kind: "blocker_started",
          summary: current["blocked_summary"].presence || "Hit a blocker.",
          current_attributes: current
        )
      elsif previous["overall_state"] == "blocked" && current["overall_state"] != "blocked"
        changes << semantic_change(
          event_kind: "blocker_cleared",
          summary: "Cleared the blocker.",
          current_attributes: current
        )
      end

      if current["last_terminal_state"].present? &&
          current["last_terminal_at"] != previous["last_terminal_at"]
        event_kind =
          case current["last_terminal_state"]
          when "completed" then "turn_completed"
          when "failed" then "turn_failed"
          else "turn_interrupted"
          end
        changes << semantic_change(
          event_kind: event_kind,
          summary: terminal_feed_summary(current),
          current_attributes: current
        )
      end

      changes.compact.uniq
    end

    def semantic_change(event_kind:, summary:, current_attributes:)
      {
        "event_kind" => event_kind,
        "summary" => summary,
        "details_payload" => {
          "overall_state" => current_attributes["overall_state"],
          "board_lane" => current_attributes["board_lane"],
          "current_owner_kind" => current_attributes["current_owner_kind"],
          "current_owner_public_id" => current_attributes["current_owner_public_id"],
          "active_subagent_count" => current_attributes["active_subagent_count"],
          "last_terminal_state" => current_attributes["last_terminal_state"],
        }.compact,
        "occurred_at" => @occurred_at,
      }
    end

    def terminal_feed_summary(current_attributes)
      current_attributes["recent_progress_summary"].presence ||
        case current_attributes["last_terminal_state"]
        when "completed" then "The turn completed."
        when "failed" then "The turn failed."
        else "The turn was interrupted."
        end
    end

    def detailed_progress_enabled?
      return @detailed_progress_enabled if instance_variable_defined?(:@detailed_progress_enabled)

      @detailed_progress_enabled = @conversation.detailed_progress_enabled?
    end
  end
end
