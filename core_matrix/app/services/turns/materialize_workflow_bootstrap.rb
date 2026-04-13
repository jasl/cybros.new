module Turns
  class MaterializeWorkflowBootstrap
    def self.call(...)
      new(...).call
    end

    def initialize(turn:)
      @turn = turn
    end

    def call
      workflow_run = nil
      failed_turn = nil

      ApplicationRecord.transaction do
        @turn.with_lock do
          @turn.reload
          return @turn.workflow_run if @turn.workflow_bootstrap_not_requested?
          return @turn.workflow_run if @turn.workflow_bootstrap_ready? && @turn.workflow_run.present?
          return nil if @turn.canceled?

          mark_materializing! unless @turn.workflow_bootstrap_materializing?
          workflow_run = @turn.workflow_run || Workflows::CreateForTurn.call(
            turn: @turn,
            root_node_key: payload.fetch("root_node_key"),
            root_node_type: payload.fetch("root_node_type"),
            decision_source: payload.fetch("decision_source"),
            metadata: payload.fetch("metadata"),
            selector_source: payload.fetch("selector_source"),
            selector: payload["selector"]
          )
          Workflows::ExecuteRun.call(workflow_run: workflow_run)
          mark_ready!
        rescue StandardError => error
          mark_failed!(error)
          failed_turn = @turn.reload
          workflow_run = nil
        end
      end

      Conversations::ProjectTurnBootstrapState.call(turn: failed_turn) if failed_turn.present?
      workflow_run
    end

    private

    def payload
      @turn.workflow_bootstrap_payload
    end

    def mark_materializing!
      @turn.update!(
        workflow_bootstrap_state: "materializing",
        workflow_bootstrap_failure_payload: {},
        workflow_bootstrap_started_at: @turn.workflow_bootstrap_started_at || Time.current,
        workflow_bootstrap_finished_at: nil
      )
    end

    def mark_ready!
      @turn.update!(
        workflow_bootstrap_state: "ready",
        workflow_bootstrap_failure_payload: {},
        workflow_bootstrap_finished_at: Time.current
      )
    end

    def mark_failed!(error)
      @turn.update!(
        workflow_bootstrap_state: "failed",
        workflow_bootstrap_failure_payload: {
          "error_class" => error.class.name,
          "error_message" => error.message,
          "retryable" => true,
        },
        workflow_bootstrap_finished_at: Time.current
      )
    end
  end
end
