module Processes
  class Activate
    def self.call(...)
      new(...).call
    end

    def initialize(process_run:, occurred_at: Time.current)
      @process_run = process_run
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @process_run.with_lock do
          @process_run.reload
          return @process_run if @process_run.running?

          raise_invalid!(@process_run, :lifecycle_state, "must be starting to activate") unless @process_run.starting?

          @process_run.workflow_node.with_lock do
            @process_run.update!(lifecycle_state: "running")

            WorkflowNodeEvent.create!(
              installation: @process_run.installation,
              workflow_run: @process_run.workflow_run,
              workflow_node: @process_run.workflow_node,
              ordinal: next_event_ordinal,
              event_kind: "status",
              payload: {
                "state" => "running",
                "process_run_id" => @process_run.id,
                "kind" => @process_run.kind,
              }
            )

            record_audit!
            broadcast_runtime_event!
            @process_run
          end
        end
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

    def record_audit!
      AuditLog.record!(
        installation: @process_run.installation,
        subject: @process_run,
        action: "process_run.started",
        metadata: {
          kind: @process_run.kind,
          workflow_node_key: @process_run.workflow_node.node_key,
        }
      )
    end

    def broadcast_runtime_event!
      Processes::BroadcastRuntimeEvent.call(
        process_run: @process_run,
        event_kind: "runtime.process_run.started",
        occurred_at: @occurred_at,
        payload: {
          "command_line" => @process_run.command_line,
          "timeout_seconds" => @process_run.timeout_seconds,
        }.compact
      )
    end
  end
end
