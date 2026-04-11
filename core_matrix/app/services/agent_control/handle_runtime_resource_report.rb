module AgentControl
  class HandleRuntimeResourceReport
    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, agent_connection: nil, execution_runtime_connection: nil, resource: nil, method_id:, payload:, occurred_at: Time.current)
      @agent_snapshot = agent_snapshot
      @agent_connection = agent_connection
      @execution_runtime_connection = execution_runtime_connection
      @resource = resource
      @method_id = method_id
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      {}
    end

    def call
      case @method_id
      when "process_started"
        handle_process_started!
      when "process_output"
        handle_process_output!
      when "process_exited"
        handle_process_exited!
      else
        raise ArgumentError, "unsupported runtime resource report #{@method_id}"
      end
    end

    private

    def handle_process_started!
      validate_process_transition_freshness!(allow_running: true)
      Processes::Activate.call(
        process_run: process_run,
        occurred_at: @occurred_at
      )
    end

    def handle_process_output!
      validate_process_output_freshness!
      Processes::BroadcastOutputChunks.call(
        process_run: process_run,
        output_chunks: @payload["output_chunks"],
        occurred_at: @occurred_at
      )
    end

    def handle_process_exited!
      validate_process_transition_freshness!(allow_running: true)
      exited_process_run = Processes::Exit.call(
        process_run: process_run,
        lifecycle_state: @payload.fetch("lifecycle_state"),
        exit_status: @payload["exit_status"],
        reason: @payload.fetch("metadata", {}).fetch("reason", "natural_exit"),
        metadata: @payload.fetch("metadata", {}),
        occurred_at: @occurred_at
      )
      settle_pending_process_close!(exited_process_run)
    end

    def validate_process_output_freshness!
      stale! unless @payload["resource_type"] == "ProcessRun"
      stale! unless process_run.running?

      execution_lease = process_run.execution_lease
      stale! unless execution_lease&.active?

      Leases::Heartbeat.call(
        execution_lease: execution_lease,
        holder_key: resolved_execution_runtime_connection.public_id,
        occurred_at: @occurred_at
      )
    rescue ArgumentError, Leases::Heartbeat::StaleLeaseError
      stale!
    end

    def validate_process_transition_freshness!(allow_running: false)
      stale! unless @payload["resource_type"] == "ProcessRun"
      allowed_states = ["starting"]
      allowed_states << "running" if allow_running
      stale! unless allowed_states.include?(process_run.lifecycle_state)

      execution_lease = process_run.execution_lease
      stale! unless execution_lease&.active?

      Leases::Heartbeat.call(
        execution_lease: execution_lease,
        holder_key: resolved_execution_runtime_connection.public_id,
        occurred_at: @occurred_at
      )
    rescue ArgumentError, Leases::Heartbeat::StaleLeaseError
      stale!
    end

    def process_run
      @process_run ||= @resource || AgentControl::ClosableResourceRegistry.find!(
        installation_id: @agent_snapshot.installation_id,
        resource_type: @payload.fetch("resource_type"),
        public_id: @payload.fetch("resource_id")
      )
    end

    def settle_pending_process_close!(process_run)
      return unless process_run.close_requested_at.present?
      return if process_run.close_closed? || process_run.close_failed?

      mailbox_item = open_close_request_for(process_run)
      return if mailbox_item.blank?

      mailbox_item.with_lock do
        process_run.with_lock do
          return unless ProgressCloseRequest::ACTIVE_STATUSES.include?(mailbox_item.status)
          return if process_run.close_closed? || process_run.close_failed?

          process_run.update!(
            close_state: "closed",
            close_acknowledged_at: process_run.close_acknowledged_at || @occurred_at,
            close_outcome_kind: "graceful",
            close_outcome_payload: process_run.close_outcome_payload.merge(
              "source" => "process_exited",
              "exit_status" => process_run.exit_status,
              "lifecycle_state" => process_run.lifecycle_state
            ).compact
          )
          mailbox_item.update!(status: "completed", completed_at: @occurred_at)
        end
      end

      conversation = process_run.conversation
      return if conversation.blank?

      Conversations::ReconcileCloseOperation.call(
        conversation: conversation,
        occurred_at: @occurred_at
      )
    end

    def open_close_request_for(process_run)
      AgentControlMailboxItem
        .where(
          installation_id: process_run.installation_id,
          item_type: "resource_close_request",
          status: ProgressCloseRequest::ACTIVE_STATUSES
        )
        .where("payload ->> 'resource_type' = ? AND payload ->> 'resource_id' = ?", "ProcessRun", process_run.public_id)
        .order(id: :desc)
        .first
    end

    def stale!
      raise Report::StaleReportError
    end

    def resolved_execution_runtime_connection
      @resolved_execution_runtime_connection ||= begin
        session = @execution_runtime_connection || ExecutionRuntimeConnections::ResolveActiveConnection.call(execution_runtime: process_run.execution_runtime)
        stale! if session.blank?
        stale! unless session.execution_runtime_id == process_run.execution_runtime_id

        session
      end
    end
  end
end
