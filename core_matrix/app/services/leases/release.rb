module Leases
  class Release
    def self.call(...)
      new(...).call
    end

    def initialize(execution_lease:, holder_key:, reason:, released_at: Time.current)
      @execution_lease = execution_lease
      @holder_key = holder_key
      @reason = reason
      @released_at = released_at
    end

    def call
      @execution_lease.with_lock do
        raise ArgumentError, "execution lease holder mismatch" unless @execution_lease.holder_key == @holder_key
        raise ArgumentError, "execution lease must be an active lease" unless @execution_lease.active?

        @execution_lease.update!(
          released_at: @released_at,
          release_reason: @reason
        )
        @execution_lease
      end
    end
  end
end
