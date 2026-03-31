module ProviderExecution
  class WithProviderRequestLease
    def self.call(...)
      new(...).call { yield }
    end

    LeaseRenewer = Struct.new(:thread, :mutex, :condition_variable, :stopped, keyword_init: true)

    def initialize(workflow_run:, request_context:, effective_catalog:, cache: Rails.cache, governor: ProviderExecution::ProviderRequestGovernor, lease_renew_interval_seconds: nil)
      @workflow_run = workflow_run
      @request_context = request_context
      @effective_catalog = effective_catalog
      @cache = cache
      @governor = governor
      @lease_renew_interval_seconds = lease_renew_interval_seconds || @governor::DEFAULT_LEASE_RENEW_INTERVAL_SECONDS
    end

    def call
      decision = @governor.acquire(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        effective_catalog: @effective_catalog,
        cache: @cache
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
          cache: @cache,
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
        cache: @cache,
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
            cache: @cache,
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
      seconds = @governor.new(
        installation: @workflow_run.installation,
        provider_handle: @request_context.provider_handle,
        effective_catalog: @effective_catalog,
        cache: @cache
      ).send(:normalize_retry_after, retry_after)
      Time.current + seconds
    end
  end
end
