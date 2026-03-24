module Leases
  class Heartbeat
    class StaleLeaseError < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(execution_lease:, holder_key:, occurred_at: Time.current)
      @execution_lease = execution_lease
      @holder_key = holder_key
      @occurred_at = occurred_at
    end

    def call
      stale_lease = false

      @execution_lease.with_lock do
        raise ArgumentError, "execution lease holder mismatch" unless @execution_lease.holder_key == @holder_key
        raise ArgumentError, "execution lease must be an active lease" unless @execution_lease.active?

        if @execution_lease.stale?(at: @occurred_at)
          @execution_lease.update!(
            released_at: @occurred_at,
            release_reason: "heartbeat_timeout"
          )
          stale_lease = true
          next
        end

        @execution_lease.update!(last_heartbeat_at: @occurred_at)
      end

      raise StaleLeaseError, "execution lease is stale" if stale_lease

      @execution_lease
    end
  end
end
