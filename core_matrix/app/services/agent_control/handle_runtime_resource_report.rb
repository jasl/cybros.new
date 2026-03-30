module AgentControl
  class HandleRuntimeResourceReport
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id:, payload:, occurred_at: Time.current)
      @deployment = deployment
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
      Processes::Exit.call(
        process_run: process_run,
        lifecycle_state: @payload.fetch("lifecycle_state"),
        exit_status: @payload["exit_status"],
        reason: @payload.fetch("metadata", {}).fetch("reason", "natural_exit"),
        metadata: @payload.fetch("metadata", {}),
        occurred_at: @occurred_at
      )
    end

    def validate_process_output_freshness!
      stale! unless @payload["resource_type"] == "ProcessRun"
      stale! unless process_run.running?
      stale! unless @deployment.execution_environment_id == process_run.execution_environment_id

      execution_lease = process_run.execution_lease
      stale! unless execution_lease&.active?

      Leases::Heartbeat.call(
        execution_lease: execution_lease,
        holder_key: @deployment.public_id,
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
      stale! unless @deployment.execution_environment_id == process_run.execution_environment_id

      execution_lease = process_run.execution_lease
      stale! unless execution_lease&.active?

      Leases::Heartbeat.call(
        execution_lease: execution_lease,
        holder_key: @deployment.public_id,
        occurred_at: @occurred_at
      )
    rescue ArgumentError, Leases::Heartbeat::StaleLeaseError
      stale!
    end

    def process_run
      @process_run ||= AgentControl::ClosableResourceRegistry.find!(
        installation_id: @deployment.installation_id,
        resource_type: @payload.fetch("resource_type"),
        public_id: @payload.fetch("resource_id")
      )
    end

    def stale!
      raise Report::StaleReportError
    end
  end
end
