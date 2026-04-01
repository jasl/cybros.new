module Conversations
  class RequestTurnPause
    DEFAULT_REASON = "user_requested".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(turn:, occurred_at: Time.current, reason: DEFAULT_REASON)
      @turn = turn
      @occurred_at = occurred_at
      @reason = reason.to_s.presence || DEFAULT_REASON
    end

    def call
      ApplicationRecord.transaction do
        with_locked_turn_context do |turn, workflow_run|
          validate_pause_target!(turn:, workflow_run:)
          establish_pause_request!(turn:, workflow_run:)
          request_mainline_resource_closes!(turn:)
          finalize_if_mainline_cleared!(workflow_run:)
        end
      end

      @turn.reload
    end

    private

    def with_locked_turn_context
      workflow_run = WorkflowRun.find_by(turn_id: @turn.id)
      return @turn.with_lock { yield @turn.reload, nil } if workflow_run.blank?

      Workflows::WithLockedWorkflowContext.call(workflow_run: workflow_run) do |current_workflow_run, turn|
        yield turn, current_workflow_run
      end
    end

    def validate_pause_target!(turn:, workflow_run:)
      raise_invalid!(turn, :lifecycle_state, "must be active to pause the current turn") unless turn.active?
      raise_invalid!(turn, :base, "must not pause after turn interruption") if turn.cancellation_reason_kind == "turn_interrupted"
      raise_invalid!(turn, :workflow_run, "must include an active workflow to pause the current turn") if workflow_run.blank?
      raise_invalid!(workflow_run, :lifecycle_state, "must be active to pause the current turn") unless workflow_run.active?
      return if workflow_run.paused_turn? || workflow_run.pause_requested?
      return if primary_running_task_run(turn:).present?

      raise_invalid!(turn, :base, "must include a resumable mainline agent task run")
    end

    def establish_pause_request!(turn:, workflow_run:)
      return if workflow_run.paused_turn?
      return if workflow_run.pause_requested?

      paused_task_run = primary_running_task_run(turn:)

      workflow_run.update!(
        Workflows::TurnPauseState.pause_requested_attributes(
          workflow_run: workflow_run,
          paused_task_run: paused_task_run,
          occurred_at: @occurred_at,
          reason: @reason
        )
      )
    end

    def request_mainline_resource_closes!(turn:)
      relations = [
        AgentTaskRun.where(turn: turn, lifecycle_state: "running"),
        reusable_subagent_step_scope(turn:),
        turn_scoped_subagent_session_scope(turn:),
      ]

      Conversations::RequestResourceCloses.call(
        relations: relations,
        request_kind: "turn_pause",
        reason_kind: "turn_paused",
        occurred_at: @occurred_at
      )
    end

    def finalize_if_mainline_cleared!(workflow_run:)
      return if workflow_run.blank?
      return unless mainline_resource_blockers_cleared?(workflow_run.turn)

      workflow_run.update!(Workflows::TurnPauseState.paused_attributes(workflow_run: workflow_run))
    end

    def mainline_resource_blockers_cleared?(turn)
      AgentTaskRun.where(turn: turn, lifecycle_state: "running").none? &&
        reusable_subagent_step_scope(turn:).none? &&
        turn_scoped_subagent_session_scope(turn:).merge(SubagentSession.close_pending_or_open).none?
    end

    def primary_running_task_run(turn:)
      AgentTaskRun.where(turn: turn, lifecycle_state: "running").order(:id).first
    end

    def reusable_subagent_step_scope(turn:)
      AgentTaskRun
        .joins(:subagent_session)
        .where(
          origin_turn: turn,
          kind: "subagent_step",
          lifecycle_state: "running",
          subagent_sessions: { scope: "conversation" }
        )
    end

    def turn_scoped_subagent_session_scope(turn:)
      SubagentSession.where(
        owner_conversation: turn.conversation,
        origin_turn: turn
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
