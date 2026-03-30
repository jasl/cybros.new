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
      when "process_output"
        handle_process_output!
      else
        raise ArgumentError, "unsupported runtime resource report #{@method_id}"
      end
    end

    private

    def handle_process_output!
      validate_process_output_freshness!
      Processes::BroadcastOutputChunks.call(
        process_run: process_run,
        output_chunks: @payload["output_chunks"],
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
