module Leases
  class Acquire
    class LeaseConflictError < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(leased_resource:, holder_key:, heartbeat_timeout_seconds:, metadata: {}, acquired_at: Time.current)
      @leased_resource = leased_resource
      @holder_key = holder_key
      @heartbeat_timeout_seconds = heartbeat_timeout_seconds
      @metadata = metadata
      @acquired_at = acquired_at
    end

    def call
      ApplicationRecord.transaction do
        existing_lease = ExecutionLease.lock.find_by(
          leased_resource: @leased_resource,
          released_at: nil
        )

        if existing_lease.present?
          expire_stale_lease!(existing_lease) if existing_lease.stale?(at: @acquired_at)
          raise LeaseConflictError, "runtime resource already has an active lease" if existing_lease.reload.active?
        end

        ExecutionLease.create!(
          installation: @leased_resource.installation,
          workflow_run: @leased_resource.workflow_run,
          workflow_node: @leased_resource.workflow_node,
          leased_resource: @leased_resource,
          holder_key: @holder_key,
          heartbeat_timeout_seconds: @heartbeat_timeout_seconds,
          acquired_at: @acquired_at,
          last_heartbeat_at: @acquired_at,
          metadata: @metadata
        )
      end
    end

    private

    def expire_stale_lease!(lease)
      lease.update!(
        released_at: @acquired_at,
        release_reason: "heartbeat_timeout"
      )
    end
  end
end
