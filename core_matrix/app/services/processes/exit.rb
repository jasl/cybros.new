module Processes
  class Exit
    TERMINAL_STATES = %w[stopped failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(process_run:, lifecycle_state:, reason:, exit_status: nil, metadata: {}, occurred_at: Time.current)
      @process_run = process_run
      @lifecycle_state = lifecycle_state
      @reason = reason
      @exit_status = exit_status
      @metadata = metadata
      @occurred_at = occurred_at
    end

    def call
      raise ArgumentError, "unsupported lifecycle state #{@lifecycle_state}" unless TERMINAL_STATES.include?(@lifecycle_state)

      ApplicationRecord.transaction do
        @process_run.with_lock do
          @process_run.reload
          return @process_run if @process_run.stopped? || @process_run.failed?

          raise_invalid!(@process_run, :lifecycle_state, "must be starting or running to exit") unless @process_run.starting? || @process_run.running?

          @process_run.workflow_node.with_lock do
            @process_run.update!(
              lifecycle_state: @lifecycle_state,
              ended_at: @process_run.ended_at || @occurred_at,
              exit_status: @exit_status,
              metadata: @process_run.metadata.merge(@metadata).merge("stop_reason" => @reason)
            )

            release_execution_lease!
            WorkflowNodeEvent.create!(
              installation: @process_run.installation,
              workflow_run: @process_run.workflow_run,
              workflow_node: @process_run.workflow_node,
              ordinal: next_event_ordinal,
              event_kind: "status",
              payload: {
                "state" => @lifecycle_state,
                "process_run_id" => @process_run.id,
                "kind" => @process_run.kind,
                "reason" => @reason,
              }.tap { |payload| payload["exit_status"] = @exit_status if @exit_status.present? }
            )

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

    def release_execution_lease!
      execution_lease = @process_run.execution_lease
      return unless execution_lease&.active?

      Leases::Release.call(
        execution_lease: execution_lease,
        holder_key: execution_lease.holder_key,
        reason: "process_exited",
        released_at: @process_run.ended_at || @occurred_at
      )
    rescue ArgumentError
      nil
    end

    def broadcast_runtime_event!
      Processes::BroadcastRuntimeEvent.call(
        process_run: @process_run,
        event_kind: "runtime.process_run.#{@lifecycle_state}",
        occurred_at: @occurred_at,
        payload: {
          "reason" => @reason,
          "exit_status" => @exit_status,
        }.compact
      )
    end
  end
end
