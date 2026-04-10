module Workflows
  class BlockNodeForProgramRequest
    MAX_DEADLOCK_RETRIES = 2

    Result = Struct.new(
      :workflow_node,
      :workflow_run,
      :turn,
      :mailbox_item,
      :request_kind,
      :deadline_at,
      keyword_init: true
    )

    METADATA_KEY = "program_mailbox_exchange".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, mailbox_item:, request_kind:, logical_work_id:, deadline_at:, occurred_at: Time.current)
      @workflow_node = workflow_node
      @mailbox_item = mailbox_item
      @request_kind = request_kind.to_s
      @logical_work_id = logical_work_id.to_s
      @deadline_at = deadline_at
      @occurred_at = occurred_at
    end

    def call
      result = nil

      with_deadlock_retry do
        ApplicationRecord.transaction do
          @workflow_node.turn.with_lock do
            @workflow_node.workflow_run.with_lock do
              @workflow_node.with_lock do
                workflow_node = @workflow_node.reload
                workflow_run = workflow_node.workflow_run.reload
                turn = workflow_node.turn.reload

                workflow_node.update!(
                  lifecycle_state: "waiting",
                  started_at: workflow_node.started_at || @occurred_at,
                  finished_at: nil,
                  metadata: workflow_node.metadata.merge(
                    METADATA_KEY => {
                      "mailbox_item_id" => @mailbox_item.public_id,
                      "logical_work_id" => @logical_work_id,
                      "request_kind" => @request_kind,
                    }
                  )
                )
                turn.update!(lifecycle_state: "waiting")
                workflow_run.update!(
                  Workflows::WaitState.cleared_detail_attributes.merge(
                    wait_state: "waiting",
                    wait_reason_kind: "agent_program_request",
                    wait_reason_payload: {
                      "mailbox_item_id" => @mailbox_item.public_id,
                      "logical_work_id" => @logical_work_id,
                      "request_kind" => @request_kind,
                    },
                    wait_resume_mode: "same_step",
                    waiting_since_at: @occurred_at,
                    blocking_resource_type: "WorkflowNode",
                    blocking_resource_id: workflow_node.public_id
                  )
                )
                append_status_event!(workflow_node:, workflow_run:)

                result = Result.new(
                  workflow_node: workflow_node,
                  workflow_run: workflow_run,
                  turn: turn,
                  mailbox_item: @mailbox_item,
                  request_kind: @request_kind,
                  deadline_at: @deadline_at
                )
              end
            end
          end
        end
      end

      schedule_resume!(result)
      result
    end

    private

    def with_deadlock_retry
      attempts = 0

      begin
        attempts += 1
        yield
      rescue ActiveRecord::Deadlocked
        raise if attempts > MAX_DEADLOCK_RETRIES

        sleep(0.01 * attempts)
        retry
      end
    end

    def append_status_event!(workflow_node:, workflow_run:)
      WorkflowNodeEvent.create!(
        installation: workflow_run.installation,
        workflow_run: workflow_run,
        workflow_node: workflow_node,
        ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
        event_kind: "status",
        payload: {
          "state" => "waiting",
          "wait_reason_kind" => "agent_program_request",
          "request_kind" => @request_kind,
          "mailbox_item_id" => @mailbox_item.public_id,
          "logical_work_id" => @logical_work_id,
        }
      )
    end

    def schedule_resume!(result)
      return if result.blank? || result.deadline_at.blank?

      Workflows::ResumeBlockedStepJob.set(wait_until: result.deadline_at).perform_later(
        result.workflow_run.public_id,
        expected_waiting_since_at_iso8601: result.workflow_run.waiting_since_at&.utc&.iso8601(6)
      )
    end
  end
end
