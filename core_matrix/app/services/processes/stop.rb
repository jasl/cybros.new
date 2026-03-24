module Processes
  class Stop
    def self.call(...)
      new(...).call
    end

    def initialize(process_run:, reason:, exit_status: nil)
      @process_run = process_run
      @reason = reason
      @exit_status = exit_status
    end

    def call
      raise_invalid!(@process_run, :lifecycle_state, "must be running to stop") unless @process_run.running?

      ApplicationRecord.transaction do
        @process_run.update!(
          lifecycle_state: "stopped",
          ended_at: Time.current,
          exit_status: @exit_status,
          metadata: @process_run.metadata.merge("stop_reason" => @reason)
        )

        WorkflowNodeEvent.create!(
          installation: @process_run.installation,
          workflow_run: @process_run.workflow_run,
          workflow_node: @process_run.workflow_node,
          ordinal: next_event_ordinal,
          event_kind: "status",
          payload: {
            "state" => "stopped",
            "process_run_id" => @process_run.id,
            "kind" => @process_run.kind,
            "reason" => @reason,
          }.tap { |payload| payload["exit_status"] = @exit_status if @exit_status.present? }
        )

        @process_run
      end
    end

    private

    def next_event_ordinal
      current_maximum = WorkflowNodeEvent.where(workflow_node: @process_run.workflow_node).maximum(:ordinal)
      current_maximum.nil? ? 0 : current_maximum + 1
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
