require "securerandom"
require "time"

module ProviderExecution
  class ProviderRequestGovernor
    DEFAULT_COOLDOWN_SECONDS = 15
    DEFAULT_LEASE_TTL_SECONDS = 5.minutes.to_i
    DEFAULT_LEASE_RENEW_INTERVAL_SECONDS = 1.minute.to_i

    Decision = Struct.new(
      :allowed,
      :provider_handle,
      :reason,
      :retry_at,
      :lease_token,
      :lease_expires_at,
      keyword_init: true
    ) do
      def allowed?
        allowed
      end

      def blocked?
        !allowed
      end
    end

    class AdmissionRefused < StandardError
      attr_reader :provider_handle, :reason, :retry_at

      def initialize(provider_handle:, reason:, retry_at:)
        super("provider request deferred for #{provider_handle}: #{reason}")
        @provider_handle = provider_handle
        @reason = reason
        @retry_at = retry_at
      end

      def retry_in_seconds(now: Time.current)
        [(@retry_at - now).ceil, 1].max
      end
    end

    def self.acquire(**kwargs)
      new(**kwargs).acquire
    end

    def self.release(lease_token:, **kwargs)
      new(**kwargs).release(lease_token: lease_token)
    end

    def self.renew(lease_token:, **kwargs)
      new(**kwargs).renew(lease_token: lease_token)
    end

    def self.record_rate_limit!(retry_after: nil, **kwargs)
      new(**kwargs).record_rate_limit!(retry_after: retry_after)
    end

    def initialize(installation:, provider_handle:, effective_catalog:, workflow_run: nil, workflow_node: nil, now: Time.current, lease_ttl_seconds: DEFAULT_LEASE_TTL_SECONDS)
      @installation = installation
      @provider_handle = provider_handle.to_s
      @effective_catalog = effective_catalog
      @workflow_run = workflow_run
      @workflow_node = workflow_node
      @now = now
      @lease_ttl_seconds = [lease_ttl_seconds.to_i, 1].max
    end

    def acquire
      admission_control = admission_control_config
      return allow! if admission_control.blank?

      with_control_lock do |control|
        expire_stale_leases!

        if control.cooldown_until.present? && control.cooldown_until > @now
          return block!(reason: "cooldown", retry_at: control.cooldown_until)
        end

        max_concurrent_requests = admission_control.fetch("max_concurrent_requests", 0).to_i
        active_leases = active_leases_relation
        if max_concurrent_requests.positive? && active_leases.count >= max_concurrent_requests
          retry_at = active_leases.minimum(:expires_at) || (@now + 1.second)
          return block!(reason: "max_concurrent_requests", retry_at: retry_at)
        end

        lease_token = SecureRandom.uuid
        lease_expires_at = @now + @lease_ttl_seconds
        ProviderRequestLease.create!(
          installation: @installation,
          workflow_run: @workflow_run,
          workflow_node: @workflow_node,
          provider_handle: @provider_handle,
          lease_token: lease_token,
          acquired_at: @now,
          last_heartbeat_at: @now,
          expires_at: lease_expires_at,
          metadata: {}
        )

        Decision.new(
          allowed: true,
          provider_handle: @provider_handle,
          reason: nil,
          retry_at: nil,
          lease_token: lease_token,
          lease_expires_at: lease_expires_at
        )
      end
    end

    def release(lease_token:)
      return if lease_token.blank?
      return if admission_control_config.blank?

      with_control_lock do |_control|
        active_leases_relation.where(lease_token: lease_token.to_s).update_all(
          released_at: @now,
          release_reason: "completed",
          updated_at: @now
        )
      end
    end

    def renew(lease_token:)
      return if lease_token.blank?
      return if admission_control_config.blank?

      active_leases_relation.where(lease_token: lease_token.to_s).update_all(
        last_heartbeat_at: @now,
        expires_at: @now + @lease_ttl_seconds,
        updated_at: @now
      )
    end

    def record_rate_limit!(retry_after: nil)
      return if admission_control_config.blank?

      with_control_lock do |control|
        expire_stale_leases!
        control.update!(
          cooldown_until: [control.cooldown_until, @now + normalize_retry_after(retry_after)].compact.max,
          last_rate_limited_at: @now,
          last_rate_limit_reason: "upstream_rate_limit"
        )
      end
    end

    private

    def admission_control_config
      @admission_control_config ||= @effective_catalog.provider_admission_control(@provider_handle)
    end

    def allow!
      Decision.new(
        allowed: true,
        provider_handle: @provider_handle,
        reason: nil,
        retry_at: nil,
        lease_token: nil,
        lease_expires_at: nil
      )
    end

    def block!(reason:, retry_at:)
      Decision.new(
        allowed: false,
        provider_handle: @provider_handle,
        reason: reason,
        retry_at: retry_at,
        lease_token: nil,
        lease_expires_at: nil
      )
    end

    def with_control_lock
      control = find_or_create_control!
      control.with_lock do
        control.reload
        yield control
      end
    end

    def find_or_create_control!
      ProviderRequestControl.find_or_create_by!(
        installation: @installation,
        provider_handle: @provider_handle
      ) do |control|
        control.metadata = {}
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def active_leases_relation
      ProviderRequestLease.active.for_provider(
        installation: @installation,
        provider_handle: @provider_handle
      )
    end

    def expire_stale_leases!
      active_leases_relation.where("expires_at <= ?", @now).update_all(
        released_at: @now,
        release_reason: "expired",
        updated_at: @now
      )
    end

    def normalize_retry_after(retry_after)
      return default_cooldown_seconds if retry_after.blank?

      integer_value = Integer(retry_after, exception: false)
      return [integer_value, 1].max if integer_value.present?

      parsed_time = Time.httpdate(retry_after.to_s)
      [((parsed_time - @now).ceil), 1].max
    rescue ArgumentError
      default_cooldown_seconds
    end

    def default_cooldown_seconds
      [admission_control_config.fetch("cooldown_seconds", DEFAULT_COOLDOWN_SECONDS).to_i, 1].max
    end
  end
end
