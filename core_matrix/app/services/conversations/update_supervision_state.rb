module Conversations
  class UpdateSupervisionState
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
      end

      state
    end

    private

    def projection_attributes(state:)
      {
        installation: @conversation.installation,
        target_conversation: @conversation,
        overall_state: overall_state,
        current_owner_kind: current_owner_kind,
        current_owner_public_id: current_owner_public_id,
        request_summary: request_summary,
        current_focus_summary: current_focus_summary,
        recent_progress_summary: recent_progress_summary,
        waiting_summary: waiting_summary,
        blocked_summary: blocked_summary,
        next_step_hint: next_step_hint,
        last_progress_at: last_progress_at,
        status_payload: status_payload
      }
    end

    def comparable_attributes(state)
      state.attributes.slice(
        "overall_state",
        "current_owner_kind",
        "current_owner_public_id",
        "request_summary",
        "current_focus_summary",
        "recent_progress_summary",
        "waiting_summary",
        "blocked_summary",
        "next_step_hint",
        "last_progress_at",
        "status_payload"
      )
    end

    def overall_state
      return "blocked" if workflow_run&.blocked?
      return "waiting" if workflow_run&.waiting?
      return task_run.supervision_state if task_run.present?
      return conversation_subagent_session.supervision_state if active_subagent_session?(conversation_subagent_session)
      return "running" if active_subagent_sessions.any?
      return workflow_terminal_state if workflow_run.present?

      "queued"
    end

    def workflow_terminal_state
      case workflow_run.lifecycle_state
      when "completed" then "completed"
      when "failed" then "failed"
      when "canceled" then "interrupted"
      else "queued"
      end
    end

    def current_owner_kind
      return "workflow_run" if workflow_run&.waiting? || workflow_run&.blocked?
      return "agent_task_run" if task_run.present?
      return "subagent_session" if active_subagent_session?(conversation_subagent_session)
      return "subagent_session" if active_subagent_sessions.first.present?

      nil
    end

    def current_owner_public_id
      return workflow_run.public_id if workflow_run&.waiting? || workflow_run&.blocked?
      return task_run.public_id if task_run.present?
      return conversation_subagent_session.public_id if active_subagent_session?(conversation_subagent_session)
      return active_subagent_sessions.first&.public_id if active_subagent_sessions.first.present?

      nil
    end

    def request_summary
      task_run&.request_summary ||
        conversation_subagent_session&.request_summary ||
        active_subagent_sessions.filter_map(&:request_summary).first
    end

    def current_focus_summary
      task_run&.current_focus_summary ||
        conversation_subagent_session&.current_focus_summary ||
        active_subagent_sessions.filter_map(&:current_focus_summary).first
    end

    def recent_progress_summary
      latest_progress_entry&.summary ||
        task_run&.recent_progress_summary ||
        conversation_subagent_session&.recent_progress_summary ||
        active_subagent_sessions.filter_map(&:recent_progress_summary).first
    end

    def waiting_summary
      return humanized_subagent_barrier_summary if workflow_run&.waiting_on_subagent_barrier?
      return task_run&.waiting_summary if task_run&.waiting_summary.present?
      return conversation_subagent_session&.waiting_summary if conversation_subagent_session&.waiting_summary.present?

      nil
    end

    def blocked_summary
      return task_run&.blocked_summary if task_run&.blocked_summary.present?
      return conversation_subagent_session&.blocked_summary if conversation_subagent_session&.blocked_summary.present?
      return workflow_run.wait_last_error_summary if workflow_run&.blocked? && workflow_run.wait_last_error_summary.present?

      nil
    end

    def next_step_hint
      task_run&.next_step_hint ||
        conversation_subagent_session&.next_step_hint ||
        active_subagent_sessions.filter_map(&:next_step_hint).first
    end

    def last_progress_at
      [
        task_run&.last_progress_at,
        conversation_subagent_session&.last_progress_at,
        active_subagent_sessions.filter_map(&:last_progress_at).max,
        workflow_run&.waiting_since_at
      ].compact.max || @occurred_at
    end

    def status_payload
      {
        "active_plan_items" => active_plan_items_payload,
        "active_subagents" => active_subagent_payloads,
        "latest_progress_entry" => latest_progress_entry_payload
      }.compact
    end

    def active_plan_items_payload
      return [] if task_run.blank?

      task_run.agent_task_plan_items.order(:position).map do |item|
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
      active_subagent_sessions.map do |session|
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
      count = active_subagent_sessions.size
      return "Waiting for child work to finish." if count.zero?

      summary = "Waiting for #{count} child #{'task'.pluralize(count)} to finish"
      focuses = active_subagent_sessions.filter_map(&:current_focus_summary).first(2)
      return "#{summary}." if focuses.empty?

      "#{summary}: #{focuses.join(', ')}."
    end

    def workflow_run
      @workflow_run ||= @conversation.workflow_runs.order(created_at: :desc).first
    end

    def task_run
      @task_run ||= AgentTaskRun.where(conversation: @conversation).order(created_at: :desc).first
    end

    def latest_progress_entry
      @latest_progress_entry ||= task_run&.agent_task_progress_entries&.order(sequence: :desc)&.first
    end

    def conversation_subagent_session
      @conversation_subagent_session ||= @conversation.subagent_session
    end

    def active_subagent_sessions
      @active_subagent_sessions ||= @conversation.owned_subagent_sessions.close_pending_or_open.order(:created_at).to_a
    end

    def active_subagent_session?(session)
      session.present? && session.supervision_state != "queued"
    end
  end
end
