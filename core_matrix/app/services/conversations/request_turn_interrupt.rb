module Conversations
  class RequestTurnInterrupt
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, occurred_at: Time.current)
      @turn = turn
      @workflow_run = turn.workflow_run
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @turn.with_lock do
          with_workflow_lock do
            fence_turn!
            cancel_blocking_human_interactions!
            cancel_queued_retry_work!
            request_mainline_resource_closes!
            finalize_if_mainline_cleared!
          end
        end

        reconcile_close_operation!
      end

      @turn.reload
    end

    private

    def with_workflow_lock(&block)
      return yield if @workflow_run.blank?

      @workflow_run.with_lock(&block)
    end

    def fence_turn!
      if @turn.active?
        @turn.update!(
          cancellation_requested_at: @turn.cancellation_requested_at || @occurred_at,
          cancellation_reason_kind: "turn_interrupted"
        )
      end

      return if @workflow_run.blank?

      @workflow_run.update!(
        cancellation_requested_at: @workflow_run.cancellation_requested_at || @occurred_at,
        cancellation_reason_kind: "turn_interrupted",
        **Workflows::WaitState.ready_attributes
      )
    end

    def cancel_blocking_human_interactions!
      HumanInteractionRequest
        .where(conversation: @turn.conversation, turn: @turn, lifecycle_state: "open", blocking: true)
        .find_each do |request|
          request.update!(
            lifecycle_state: "canceled",
            resolution_kind: "canceled",
            result_payload: request.result_payload.merge("reason" => "turn_interrupted"),
            resolved_at: @occurred_at
          )
        end
    end

    def cancel_queued_retry_work!
      AgentTaskRun.where(turn: @turn, lifecycle_state: "queued").find_each do |task_run|
        task_run.update!(
          lifecycle_state: "canceled",
          started_at: task_run.started_at || @occurred_at,
          finished_at: @occurred_at,
          terminal_payload: task_run.terminal_payload.merge("cancellation_reason_kind" => "turn_interrupted")
        )
        AgentControlMailboxItem.where(agent_task_run: task_run, status: %w[queued leased]).update_all(
          status: "canceled",
          completed_at: @occurred_at,
          leased_to_agent_deployment_id: nil,
          leased_at: nil,
          lease_expires_at: nil,
          updated_at: @occurred_at
        )
      end
    end

    def request_mainline_resource_closes!
      relations = [
        AgentTaskRun.where(turn: @turn, lifecycle_state: "running"),
        ProcessRun.where(turn: @turn, lifecycle_state: "running", kind: "turn_command")
      ]
      relations << SubagentRun.where(workflow_run: @workflow_run, lifecycle_state: "running") if @workflow_run.present?

      Conversations::RequestResourceCloses.call(
        relations: relations,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupted",
        occurred_at: @occurred_at
      )
    end

    def finalize_if_mainline_cleared!
      return unless mainline_resource_blockers_cleared?

      @workflow_run&.update!(
        lifecycle_state: "canceled",
        **Workflows::WaitState.ready_attributes
      )

      @turn.update!(lifecycle_state: "canceled")
    end

    def mainline_resource_blockers_cleared?
      AgentTaskRun.where(turn: @turn, lifecycle_state: "running").none? &&
        HumanInteractionRequest.where(conversation: @turn.conversation, turn: @turn, lifecycle_state: "open", blocking: true).none? &&
        ProcessRun.where(turn: @turn, lifecycle_state: "running", kind: "turn_command").none? &&
        (@workflow_run.blank? || SubagentRun.where(workflow_run: @workflow_run, lifecycle_state: "running").none?)
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
