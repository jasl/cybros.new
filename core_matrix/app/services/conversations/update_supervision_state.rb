module Conversations
  class UpdateSupervisionState
    ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze
    TERMINAL_TASK_LIFECYCLE_STATES = %w[completed failed interrupted canceled].freeze
    ACTIVE_SUBAGENT_OBSERVED_STATUSES = %w[running waiting].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current)
      @conversation = conversation
      @occurred_at = occurred_at
    end

    def call
      state = @conversation.conversation_supervision_state ||
        @conversation.build_conversation_supervision_state(
          installation: @conversation.installation,
          status_payload: {}
        )
      previous_attributes = state.new_record? ? {} : comparable_attributes(state)
      next_attributes = projection_attributes(state:)
      changed = state.new_record? || previous_attributes != next_attributes

      if changed
        state.assign_attributes(
          next_attributes.merge(
            projection_version: state.projection_version.to_i + 1
          )
        )
        state.save!
        ConversationSupervision::PublishUpdate.call(
          conversation_supervision_state: state,
          previous_attributes: previous_attributes
        )
      end

      state
    end

    private

    def projection_attributes(state:)
      {
        installation: @conversation.installation,
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
        status_payload: status_payload
      }
    end

    def comparable_attributes(state)
      state.attributes.slice(
        "overall_state",
        "last_terminal_state",
        "last_terminal_at",
        "current_owner_kind",
        "current_owner_public_id",
        "request_summary",
        "current_focus_summary",
        "recent_progress_summary",
        "waiting_summary",
        "blocked_summary",
        "next_step_hint",
        "last_progress_at",
        "board_lane",
        "lane_changed_at",
        "retry_due_at",
        "active_plan_item_count",
        "completed_plan_item_count",
        "active_subagent_count",
        "board_badges",
        "status_payload"
      )
    end

    def overall_state
      return "blocked" if workflow_run&.blocked?
      return "waiting" if workflow_run&.waiting?
      return current_task_run.supervision_state if current_task_run.present?
      return active_conversation_subagent_session.supervision_state if active_conversation_subagent_session.present?
      return owned_subagent_overall_state if active_owned_subagent_sessions.any?
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
      return "workflow_run" if workflow_run&.waiting? || workflow_run&.blocked?
      return "agent_task_run" if current_task_run.present?
      return "subagent_session" if active_conversation_subagent_session.present?
      return "subagent_session" if active_owned_subagent_sessions.first.present?
      return "workflow_run" if active_workflow?

      nil
    end

    def current_owner_public_id
      return workflow_run.public_id if workflow_run&.waiting? || workflow_run&.blocked?
      return current_task_run.public_id if current_task_run.present?
      return active_conversation_subagent_session.public_id if active_conversation_subagent_session.present?
      return active_owned_subagent_sessions.first&.public_id if active_owned_subagent_sessions.first.present?
      return workflow_run.public_id if active_workflow?

      nil
    end

    def request_summary
      current_task_run&.request_summary ||
        active_conversation_subagent_session&.request_summary ||
        active_owned_subagent_sessions.filter_map(&:request_summary).first ||
        latest_task_run&.request_summary
    end

    def current_focus_summary
      current_task_run&.current_focus_summary ||
        active_conversation_subagent_session&.current_focus_summary ||
        active_owned_subagent_sessions.filter_map(&:current_focus_summary).first
    end

    def recent_progress_summary
      current_task_progress_entry&.summary ||
        current_task_run&.recent_progress_summary ||
        active_conversation_subagent_session&.recent_progress_summary ||
        active_owned_subagent_sessions.filter_map(&:recent_progress_summary).first ||
        latest_progress_entry&.summary ||
        latest_task_run&.recent_progress_summary
    end

    def waiting_summary
      return humanized_subagent_barrier_summary if workflow_run&.waiting_on_subagent_barrier?
      return current_task_run&.waiting_summary if current_task_run&.waiting_summary.present?
      return active_conversation_subagent_session&.waiting_summary if active_conversation_subagent_session&.waiting_summary.present?
      return active_owned_subagent_sessions.filter_map(&:waiting_summary).first if workflow_run&.waiting?

      nil
    end

    def blocked_summary
      return current_task_run&.blocked_summary if current_task_run&.blocked_summary.present?
      return active_conversation_subagent_session&.blocked_summary if active_conversation_subagent_session&.blocked_summary.present?
      return active_owned_subagent_sessions.filter_map(&:blocked_summary).first if workflow_run&.blocked?
      return workflow_run.wait_last_error_summary if workflow_run&.blocked? && workflow_run.wait_last_error_summary.present?

      nil
    end

    def next_step_hint
      current_task_run&.next_step_hint ||
        active_conversation_subagent_session&.next_step_hint ||
        active_owned_subagent_sessions.filter_map(&:next_step_hint).first
    end

    def last_progress_at
      [
        current_task_run&.last_progress_at,
        active_conversation_subagent_session&.last_progress_at,
        active_owned_subagent_sessions.filter_map(&:last_progress_at).max,
        latest_task_run&.last_progress_at,
        last_terminal_at,
        workflow_run&.waiting_since_at
      ].compact.max || @occurred_at
    end

    def board_lane
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
      return 0 if current_task_run.blank?

      current_task_run.agent_task_plan_items.where.not(status: %w[completed canceled]).count
    end

    def completed_plan_item_count
      return 0 if current_task_run.blank?

      current_task_run.agent_task_plan_items.where(status: "completed").count
    end

    def active_subagent_count
      active_owned_subagent_sessions.count
    end

    def board_badges
      badges = []
      badges << "#{active_plan_item_count} active plan item#{'s' unless active_plan_item_count == 1}" if active_plan_item_count.positive?
      badges << "#{active_subagent_count} child task#{'s' unless active_subagent_count == 1}" if active_subagent_count.positive?
      badges << "retry pending" if retry_due_at.present?
      badges
    end

    def status_payload
      {
        "active_plan_items" => active_plan_items_payload,
        "active_subagents" => active_subagent_payloads,
        "latest_progress_entry" => latest_progress_entry_payload
      }.compact
    end

    def active_plan_items_payload
      return [] if current_task_run.blank?

      current_task_run.agent_task_plan_items.order(:position).map do |item|
        {
          "item_key" => item.item_key,
          "title" => item.title,
          "status" => item.status,
          "position" => item.position,
          "delegated_subagent_session_id" => item.delegated_subagent_session&.public_id
        }.compact
      end
    end

    def active_subagent_payloads
      active_owned_subagent_sessions.map do |session|
        {
          "subagent_session_id" => session.public_id,
          "observed_status" => session.observed_status,
          "supervision_state" => session.supervision_state,
          "profile_key" => session.profile_key,
          "current_focus_summary" => session.current_focus_summary,
          "waiting_summary" => session.waiting_summary,
          "blocked_summary" => session.blocked_summary,
          "next_step_hint" => session.next_step_hint
        }.compact
      end
    end

    def latest_progress_entry_payload
      return if latest_progress_entry.blank?

      {
        "agent_task_run_id" => latest_progress_entry.agent_task_run.public_id,
        "sequence" => latest_progress_entry.sequence,
        "entry_kind" => latest_progress_entry.entry_kind,
        "summary" => latest_progress_entry.summary,
        "occurred_at" => latest_progress_entry.occurred_at.iso8601
      }.compact
    end

    def humanized_subagent_barrier_summary
      sessions = barrier_aware_subagent_sessions
      count = sessions.size
      return "Waiting for child work to finish." if count.zero?

      summary = "Waiting for #{count} child #{'task'.pluralize(count)} to finish"
      focuses = sessions.filter_map(&:current_focus_summary).first(2)
      return "#{summary}." if focuses.empty?

      "#{summary}: #{focuses.join(', ')}."
    end

    def workflow_run
      @workflow_run ||= @conversation.workflow_runs.order(created_at: :desc).first
    end

    def current_task_run
      @current_task_run ||= AgentTaskRun
        .where(conversation: @conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
        .order(created_at: :desc)
        .first
    end

    def latest_task_run
      @latest_task_run ||= AgentTaskRun.where(conversation: @conversation).order(created_at: :desc).first
    end

    def latest_terminal_task_run
      @latest_terminal_task_run ||= AgentTaskRun
        .where(conversation: @conversation, lifecycle_state: TERMINAL_TASK_LIFECYCLE_STATES)
        .where.not(finished_at: nil)
        .order(finished_at: :desc, created_at: :desc)
        .first
    end

    def latest_progress_entry
      @latest_progress_entry ||= latest_task_run&.agent_task_progress_entries&.order(sequence: :desc)&.first
    end

    def current_task_progress_entry
      @current_task_progress_entry ||= current_task_run&.agent_task_progress_entries&.order(sequence: :desc)&.first
    end

    def conversation_subagent_session
      @conversation_subagent_session ||= @conversation.subagent_session
    end

    def active_conversation_subagent_session
      session = conversation_subagent_session
      return unless active_subagent_session?(session)

      session
    end

    def active_owned_subagent_sessions
      @active_owned_subagent_sessions ||= @conversation.owned_subagent_sessions
        .close_pending_or_open
        .where(observed_status: ACTIVE_SUBAGENT_OBSERVED_STATUSES)
        .order(:created_at)
        .to_a
    end

    def barrier_subagent_sessions
      return [] unless workflow_run&.waiting_on_subagent_barrier?

      workflow_run.subagent_barrier_sessions.select { |session| active_subagent_session?(session) }
    end

    def barrier_aware_subagent_sessions
      sessions = barrier_subagent_sessions
      return sessions if sessions.present?

      active_owned_subagent_sessions
    end

    def active_subagent_session?(session)
      session.present? &&
        session.close_pending_or_open? &&
        ACTIVE_SUBAGENT_OBSERVED_STATUSES.include?(session.observed_status)
    end

    def owned_subagent_overall_state
      states = active_owned_subagent_sessions.map(&:supervision_state)
      return "blocked" if states.include?("blocked")
      return "waiting" if states.include?("waiting")

      "running"
    end

    def board_lane_active_subagent_count
      return barrier_aware_subagent_sessions.count if workflow_run&.waiting_on_subagent_barrier?

      active_subagent_count
    end

    def workflow_terminal?
      workflow_run.present? && %w[completed failed canceled].include?(workflow_run.lifecycle_state)
    end

    def active_workflow?
      workflow_run&.active?
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
  end
end
