module ProviderExecution
  class WithProviderRequestLease
    def self.call(...)
      new(...).call { yield }
    end

    LeaseRenewer = Struct.new(:thread, :mutex, :condition_variable, :stopped, keyword_init: true)

    def initialize(workflow_run:, request_context:, effective_catalog:, workflow_node: nil, governor: ProviderExecution::ProviderRequestGovernor, lease_renew_interval_seconds: nil)
      @workflow_run = workflow_run
      @request_context = request_context
      @effective_catalog = effective_catalog
      @workflow_node = workflow_node
      @governor = governor
      @lease_renew_interval_seconds = lease_renew_interval_seconds || @governor::DEFAULT_LEASE_RENEW_INTERVAL_SECONDS
    end

    def call
      decision = @governor.acquire(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        effective_catalog: @effective_catalog,
        workflow_run: @workflow_run,
        workflow_node: @workflow_node
      )

      unless decision.allowed?
        raise ProviderExecution::ProviderRequestGovernor::AdmissionRefused.new(
          provider_handle: decision.provider_handle,
          reason: decision.reason,
          retry_at: decision.retry_at
        )
      end

      renewer = start_lease_renewer(decision)
      yield
    rescue SimpleInference::HTTPError => error
      if error.status.to_i == 429
        @governor.record_rate_limit!(
          installation: @workflow_run.installation,
          provider_handle: @request_context.provider_handle,
          effective_catalog: @effective_catalog,
          retry_after: error.headers["retry-after"] || error.headers["Retry-After"]
        )

        raise ProviderExecution::ProviderRequestGovernor::AdmissionRefused.new(
          provider_handle: @request_context.provider_handle,
          reason: "upstream_rate_limit",
          retry_at: retry_at_for(error)
        )
      end

      raise
    ensure
      stop_lease_renewer(renewer)

      @governor.release(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        effective_catalog: @effective_catalog,
        lease_token: decision&.lease_token
      )
    end

    private

    def start_lease_renewer(decision)
      interval = @lease_renew_interval_seconds.to_f
      return nil if decision&.lease_token.blank? || interval <= 0

      renewer = LeaseRenewer.new(
        mutex: Mutex.new,
        condition_variable: ConditionVariable.new,
        stopped: false
      )
      renewer.thread = Thread.new do
        loop do
          stopped = renewer.mutex.synchronize do
            next true if renewer.stopped
            renewer.condition_variable.wait(renewer.mutex, interval)
            renewer.stopped
          end
          break if stopped

          @governor.renew(
            installation: @workflow_run.installation,
            provider_handle: @request_context.provider_handle,
            effective_catalog: @effective_catalog,
            lease_token: decision.lease_token
          )
        end
      rescue StandardError => error
        Rails.logger.warn("provider lease renewer stopped unexpectedly: #{error.class}: #{error.message}")
      end

      renewer
    end

    def stop_lease_renewer(renewer)
      return if renewer.blank?

      renewer.mutex.synchronize do
        renewer.stopped = true
        renewer.condition_variable.broadcast
      end
      renewer.thread.join
    end

    def retry_at_for(error)
      retry_after = error.headers["retry-after"] || error.headers["Retry-After"]
      seconds = @governor.retry_after_seconds_for(
        retry_after:,
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        effective_catalog: @effective_catalog
      )
      Time.current + seconds
    end
  end
end
