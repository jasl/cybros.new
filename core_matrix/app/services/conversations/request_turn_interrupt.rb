module Conversations
  class RequestTurnInterrupt
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, occurred_at: Time.current)
      @turn = turn
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        with_locked_turn_context do |turn, workflow_run|
          fence_turn!(turn:, workflow_run:)
          cancel_blocking_human_interactions!(turn:)
          cancel_queued_retry_work!(turn:)
          request_mainline_resource_closes!(turn:)
          finalize_if_mainline_cleared!(turn:, workflow_run:)
        end

        reconcile_close_operation!
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

    def fence_turn!(turn:, workflow_run:)
      if turn.active?
        turn.update!(
          cancellation_requested_at: turn.cancellation_requested_at || @occurred_at,
          cancellation_reason_kind: "turn_interrupted"
        )
      end

      return if workflow_run.blank?

      workflow_run.update!(
        cancellation_requested_at: workflow_run.cancellation_requested_at || @occurred_at,
        cancellation_reason_kind: "turn_interrupted",
        **Workflows::WaitState.ready_attributes
      )
    end

    def cancel_blocking_human_interactions!(turn:)
      HumanInteractionRequest
        .where(conversation: turn.conversation, turn: turn, lifecycle_state: "open", blocking: true)
        .find_each do |request|
          request.update!(
            lifecycle_state: "canceled",
            resolution_kind: "canceled",
            result_payload: request.result_payload.merge("reason" => "turn_interrupted"),
            resolved_at: @occurred_at
          )
        end
    end

    def cancel_queued_retry_work!(turn:)
      AgentTaskRun.where(turn: turn, lifecycle_state: "queued").find_each do |task_run|
        task_run.update!(
          lifecycle_state: "canceled",
          started_at: task_run.started_at || @occurred_at,
          finished_at: @occurred_at,
          terminal_payload: task_run.terminal_payload.merge("cancellation_reason_kind" => "turn_interrupted")
        )
        AgentControlMailboxItem.where(agent_task_run: task_run, status: %w[queued leased]).update_all(
          status: "canceled",
          completed_at: @occurred_at,
          leased_to_agent_session_id: nil,
          leased_to_execution_session_id: nil,
          leased_at: nil,
          lease_expires_at: nil,
          updated_at: @occurred_at
        )
      end
    end

    def request_mainline_resource_closes!(turn:)
      relations = [
        AgentTaskRun.where(turn: turn, lifecycle_state: "running"),
        reusable_subagent_step_scope(turn:),
        turn_scoped_subagent_session_scope(turn:),
      ]

      Conversations::RequestResourceCloses.call(
        relations: relations,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupted",
        occurred_at: @occurred_at
      )
    end

    def finalize_if_mainline_cleared!(turn:, workflow_run:)
      return unless mainline_resource_blockers_cleared?(turn:)

      workflow_run&.update!(
        lifecycle_state: "canceled",
        **Workflows::WaitState.ready_attributes
      )

      turn.update!(lifecycle_state: "canceled")
    end

    def mainline_resource_blockers_cleared?(turn:)
      AgentTaskRun.where(turn: turn, lifecycle_state: "running").none? &&
        HumanInteractionRequest.where(conversation: turn.conversation, turn: turn, lifecycle_state: "open", blocking: true).none? &&
        reusable_subagent_step_scope(turn:).none? &&
        turn_scoped_subagent_session_scope(turn:).merge(SubagentSession.close_pending_or_open).none?
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

    def reconcile_close_operation!
      conversation = @turn.conversation
      return if conversation.unfinished_close_operation.blank?

      Conversations::ReconcileCloseOperation.call(
        conversation: conversation,
        occurred_at: @occurred_at
      )
    end
  end
end
