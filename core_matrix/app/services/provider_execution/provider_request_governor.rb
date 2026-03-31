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

    def self.acquire(installation:, provider_handle:, effective_catalog:, cache: Rails.cache, now: Time.current, lease_ttl_seconds: DEFAULT_LEASE_TTL_SECONDS)
      new(
        installation: installation,
        provider_handle: provider_handle,
        effective_catalog: effective_catalog,
        cache: cache,
        now: now,
        lease_ttl_seconds: lease_ttl_seconds
      ).acquire
    end

    def self.release(installation:, provider_handle:, effective_catalog:, cache: Rails.cache, lease_token:, now: Time.current, lease_ttl_seconds: DEFAULT_LEASE_TTL_SECONDS)
      new(
        installation: installation,
        provider_handle: provider_handle,
        effective_catalog: effective_catalog,
        cache: cache,
        now: now,
        lease_ttl_seconds: lease_ttl_seconds
      ).release(lease_token: lease_token)
    end

    def self.renew(installation:, provider_handle:, effective_catalog:, cache: Rails.cache, lease_token:, now: Time.current, lease_ttl_seconds: DEFAULT_LEASE_TTL_SECONDS)
      new(
        installation: installation,
        provider_handle: provider_handle,
        effective_catalog: effective_catalog,
        cache: cache,
        now: now,
        lease_ttl_seconds: lease_ttl_seconds
      ).renew(lease_token: lease_token)
    end

    def self.record_rate_limit!(installation:, provider_handle:, effective_catalog:, cache: Rails.cache, retry_after: nil, now: Time.current, lease_ttl_seconds: DEFAULT_LEASE_TTL_SECONDS)
      new(
        installation: installation,
        provider_handle: provider_handle,
        effective_catalog: effective_catalog,
        cache: cache,
        now: now,
        lease_ttl_seconds: lease_ttl_seconds
      ).record_rate_limit!(retry_after: retry_after)
    end

    def initialize(installation:, provider_handle:, effective_catalog:, cache: Rails.cache, now: Time.current, lease_ttl_seconds: DEFAULT_LEASE_TTL_SECONDS)
      @installation = installation
      @provider_handle = provider_handle.to_s
      @effective_catalog = effective_catalog
      @cache = cache
      @now = now
      @lease_ttl_seconds = [lease_ttl_seconds.to_i, 1].max
    end

    def acquire
      governor = governor_config
      return allow! if governor.blank?

      with_lock do
        leases = prune_expired_leases(read_leases)
        throttle_timestamps = prune_expired_timestamps(read_throttle_timestamps, governor)
        cooldown_until = read_cooldown_until

        if cooldown_until.present? && cooldown_until > @now
          persist_state(leases:, throttle_timestamps:, cooldown_until:)
          return block!(reason: "cooldown", retry_at: cooldown_until)
        end

        max_concurrent_requests = governor["max_concurrent_requests"].to_i
        if max_concurrent_requests.positive? && leases.size >= max_concurrent_requests
          persist_state(leases:, throttle_timestamps:, cooldown_until: nil)
          retry_at = Time.at(leases.values.min).utc
          return block!(reason: "max_concurrent_requests", retry_at:)
        end

        throttle_limit = governor["throttle_limit"].to_i
        throttle_period_seconds = governor["throttle_period_seconds"].to_i
        if throttle_limit.positive? &&
            throttle_period_seconds.positive? &&
            throttle_timestamps.size >= throttle_limit
          retry_at = Time.at(throttle_timestamps.first + throttle_period_seconds).utc
          persist_state(leases:, throttle_timestamps:, cooldown_until: nil)
          return block!(reason: "throttle_limit", retry_at:)
        end

        lease_token = SecureRandom.uuid
        lease_expires_at = @now + @lease_ttl_seconds
        leases[lease_token] = lease_expires_at.to_f
        throttle_timestamps << @now.to_f

        persist_state(leases:, throttle_timestamps:, cooldown_until: nil)

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
      return if governor_config.blank?

      with_lock do
        leases = prune_expired_leases(read_leases)
        leases.delete(lease_token.to_s)
        persist_state(
          leases: leases,
          throttle_timestamps: prune_expired_timestamps(read_throttle_timestamps, governor_config),
          cooldown_until: read_cooldown_until
        )
      end
    end

    def renew(lease_token:)
      return if lease_token.blank?
      return if governor_config.blank?

      with_lock do
        leases = prune_expired_leases(read_leases)
        token = lease_token.to_s
        next unless leases.key?(token)

        leases[token] = (@now + @lease_ttl_seconds).to_f
        persist_state(
          leases: leases,
          throttle_timestamps: prune_expired_timestamps(read_throttle_timestamps, governor_config),
          cooldown_until: read_cooldown_until
        )
      end
    end

    def record_rate_limit!(retry_after: nil)
      return if governor_config.blank?

      cooldown_until = @now + normalize_retry_after(retry_after)

      with_lock do
        persist_state(
          leases: prune_expired_leases(read_leases),
          throttle_timestamps: prune_expired_timestamps(read_throttle_timestamps, governor_config),
          cooldown_until: [read_cooldown_until, cooldown_until].compact.max
        )
      end
    end

    private

    def governor_config
      @governor_config ||= @effective_catalog.provider_governor(@provider_handle)
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

    def lock_name
      "provider-request-governor:#{installation_cache_key}:#{@provider_handle}"
    end

    def installation_cache_key
      @installation&.id || "global"
    end

    def leases_cache_key
      "provider-request-governor:leases:#{installation_cache_key}:#{@provider_handle}"
    end

    def throttle_cache_key
      "provider-request-governor:throttle:#{installation_cache_key}:#{@provider_handle}"
    end

    def cooldown_cache_key
      "provider-request-governor:cooldown:#{installation_cache_key}:#{@provider_handle}"
    end

    def with_lock(&block)
      ProviderPolicy.with_advisory_lock(lock_name, &block)
    end

    def read_leases
      (@cache.read(leases_cache_key) || {}).transform_values(&:to_f)
    end

    def read_throttle_timestamps
      Array(@cache.read(throttle_cache_key)).map(&:to_f)
    end

    def read_cooldown_until
      value = @cache.read(cooldown_cache_key)
      return nil if value.blank?

      Time.at(value.to_f).utc
    end

    def persist_state(leases:, throttle_timestamps:, cooldown_until:)
      @cache.write(leases_cache_key, leases, expires_in: DEFAULT_LEASE_TTL_SECONDS)

      throttle_expires_in = [governor_config["throttle_period_seconds"].to_i, DEFAULT_COOLDOWN_SECONDS].max
      @cache.write(throttle_cache_key, throttle_timestamps, expires_in: throttle_expires_in)

      if cooldown_until.present? && cooldown_until > @now
        @cache.write(cooldown_cache_key, cooldown_until.to_f, expires_in: [(cooldown_until - @now).ceil, 1].max)
      else
        @cache.delete(cooldown_cache_key)
      end
    end

    def prune_expired_leases(leases)
      now_f = @now.to_f
      leases.each_with_object({}) do |(token, expires_at), active|
        active[token] = expires_at if expires_at > now_f
      end
    end

    def prune_expired_timestamps(timestamps, governor)
      period = governor["throttle_period_seconds"].to_i
      return [] if period <= 0

      cutoff = @now.to_f - period
      timestamps.select { |timestamp| timestamp >= cutoff }.sort
    end

    def normalize_retry_after(retry_after)
      return DEFAULT_COOLDOWN_SECONDS if retry_after.blank?

      if retry_after.is_a?(Numeric)
        return [retry_after.to_i, 1].max
      end

      string = retry_after.to_s.strip
      return [string.to_i, 1].max if string.match?(/\A\d+\z/)

      parsed_time = Time.httpdate(string)
      [((parsed_time - @now).ceil), 1].max
    rescue ArgumentError
      DEFAULT_COOLDOWN_SECONDS
    end
  end
end
