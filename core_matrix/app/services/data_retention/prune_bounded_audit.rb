module DataRetention
  class PruneBoundedAudit
    ZERO_RESULT = {
      control_requests_deleted: 0,
      usage_events_deleted: 0,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(cutoff:, batch_size:)
      @cutoff = cutoff
      @batch_size = batch_size
    end

    def call
      totals = ZERO_RESULT.dup

      loop do
        batch = delete_batch
        totals.merge!(batch) { |_key, total, value| total + value }
        break if batch.values.all?(&:zero?)
      end

      totals
    end

    private

    attr_reader :cutoff, :batch_size

    def delete_batch
      {
        control_requests_deleted: delete_control_request_batch,
        usage_events_deleted: delete_usage_event_batch,
      }
    end

    def delete_control_request_batch
      ids = ConversationControlRequest
        .where(lifecycle_state: ConversationControlRequest::TERMINAL_LIFECYCLE_STATES)
        .where("COALESCE(completed_at, updated_at) < ?", cutoff)
        .order(:id)
        .limit(batch_size)
        .pluck(:id)

      return 0 if ids.empty?

      ConversationControlRequest.where(id: ids).delete_all
    end

    def delete_usage_event_batch
      ids = UsageEvent
        .where("occurred_at < ?", cutoff)
        .order(:id)
        .limit(batch_size)
        .pluck(:id)

      return 0 if ids.empty?

      UsageEvent.where(id: ids).delete_all
    end
  end
end
