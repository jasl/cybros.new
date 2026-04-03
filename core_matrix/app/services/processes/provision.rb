module Processes
  class Provision
    LEASE_TIMEOUT_SECONDS = 30

    Result = Struct.new(:process_run, :created, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, execution_runtime:, kind:, command_line:, timeout_seconds: nil, origin_message: nil, metadata: {}, idempotency_key: nil)
      @workflow_node = workflow_node
      @execution_runtime = execution_runtime
      @kind = kind
      @command_line = command_line
      @timeout_seconds = timeout_seconds
      @origin_message = origin_message
      @metadata = metadata
      @idempotency_key = idempotency_key
    end

    def call
      existing = existing_process_run
      return Result.new(process_run: existing, created: false) if existing.present?

      process_run = provision_process_run!
      Result.new(process_run: process_run, created: true)
    rescue ActiveRecord::RecordNotUnique
      Result.new(process_run: existing_process_run!, created: false)
    end

    private

    def provision_process_run!
      ApplicationRecord.transaction do
        @workflow_node.with_lock do
          process_run = ProcessRun.create!(
            installation: @workflow_node.installation,
            workflow_node: @workflow_node,
            execution_runtime: @execution_runtime,
            conversation: @workflow_node.workflow_run.conversation,
            turn: @workflow_node.workflow_run.turn,
            origin_message: @origin_message,
            kind: @kind,
            lifecycle_state: "starting",
            command_line: @command_line,
            timeout_seconds: @timeout_seconds,
            metadata: @metadata,
            idempotency_key: @idempotency_key,
            started_at: Time.current
          )

          acquire_process_lease!(process_run)
          append_status_event!(process_run: process_run, state: "starting")
          process_run
        end
      end
    end

    def append_status_event!(process_run:, state:)
      WorkflowNodeEvent.create!(
        installation: @workflow_node.installation,
        workflow_run: @workflow_node.workflow_run,
        workflow_node: @workflow_node,
        ordinal: next_event_ordinal,
        event_kind: "status",
        payload: {
          "state" => state,
          "process_run_id" => process_run.id,
          "kind" => process_run.kind,
        }
      )
    end

    def acquire_process_lease!(process_run)
      execution_session = ExecutionSessions::ResolveActiveSession.call(
        execution_runtime: process_run.execution_runtime
      )
      return if execution_session.blank?

      Leases::Acquire.call(
        leased_resource: process_run,
        holder_key: execution_session.public_id,
        heartbeat_timeout_seconds: LEASE_TIMEOUT_SECONDS
      )
    end

    def next_event_ordinal
      current_maximum = WorkflowNodeEvent.where(workflow_node: @workflow_node).maximum(:ordinal)
      current_maximum.nil? ? 0 : current_maximum + 1
    end

    def existing_process_run
      return if @idempotency_key.blank?

      ProcessRun.find_by(
        workflow_node: @workflow_node,
        idempotency_key: @idempotency_key
      )
    end

    def existing_process_run!
      ProcessRun.find_by!(
        workflow_node: @workflow_node,
        idempotency_key: @idempotency_key
      )
    end
  end
end
