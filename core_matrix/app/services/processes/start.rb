module Processes
  class Start
    LEASE_TIMEOUT_SECONDS = 30

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, execution_environment:, kind:, command_line:, timeout_seconds: nil, origin_message: nil, metadata: {}, policy_sensitive: nil)
      @workflow_node = workflow_node
      @execution_environment = execution_environment
      @kind = kind
      @command_line = command_line
      @timeout_seconds = timeout_seconds
      @origin_message = origin_message
      @metadata = metadata
      @policy_sensitive = policy_sensitive
    end

    def call
      ApplicationRecord.transaction do
        @workflow_node.with_lock do
          process_run = ProcessRun.create!(
            installation: @workflow_node.installation,
            workflow_node: @workflow_node,
            execution_environment: @execution_environment,
            conversation: @workflow_node.workflow_run.conversation,
            turn: @workflow_node.workflow_run.turn,
            origin_message: @origin_message,
            kind: @kind,
            lifecycle_state: "running",
            command_line: @command_line,
            timeout_seconds: @timeout_seconds,
            metadata: @metadata
          )

          acquire_process_lease!(process_run)
          append_status_event!(process_run: process_run, state: "running")
          record_audit!(process_run) if policy_sensitive?
          broadcast_runtime_event!(process_run)
          process_run
        end
      end
    end

    private

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
      delivery_endpoint = ExecutionEnvironments::ResolveDeliveryEndpoint.call(
        execution_environment: process_run.execution_environment
      )
      return if delivery_endpoint.blank?

      Leases::Acquire.call(
        leased_resource: process_run,
        holder_key: delivery_endpoint.public_id,
        heartbeat_timeout_seconds: LEASE_TIMEOUT_SECONDS
      )
    end

    def next_event_ordinal
      current_maximum = WorkflowNodeEvent.where(workflow_node: @workflow_node).maximum(:ordinal)
      current_maximum.nil? ? 0 : current_maximum + 1
    end

    def policy_sensitive?
      return @policy_sensitive unless @policy_sensitive.nil?

      @workflow_node.metadata["policy_sensitive"] == true
    end

    def record_audit!(process_run)
      AuditLog.record!(
        installation: @workflow_node.installation,
        subject: process_run,
        action: "process_run.started",
        metadata: {
          kind: process_run.kind,
          workflow_node_key: @workflow_node.node_key,
        }
      )
    end

    def broadcast_runtime_event!(process_run)
      Processes::BroadcastRuntimeEvent.call(
        process_run: process_run,
        event_kind: "runtime.process_run.started",
        payload: {
          "command_line" => process_run.command_line,
          "timeout_seconds" => process_run.timeout_seconds,
        }.compact
      )
    end
  end
end
