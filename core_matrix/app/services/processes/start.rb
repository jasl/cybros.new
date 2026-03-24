module Processes
  class Start
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

        append_status_event!(process_run: process_run, state: "running")
        record_audit!(process_run) if policy_sensitive?
        process_run
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
  end
end
