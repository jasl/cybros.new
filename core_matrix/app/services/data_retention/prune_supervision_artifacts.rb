module DataRetention
  class PruneSupervisionArtifacts
    ZERO_RESULT = {
      sessions_deleted: 0,
      snapshots_deleted: 0,
      messages_deleted: 0,
      control_requests_deleted: 0,
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
      session_ids = stale_session_ids
      return ZERO_RESULT.dup if session_ids.empty?

      {
        control_requests_deleted: ConversationControlRequest.where(conversation_supervision_session_id: session_ids).delete_all,
        messages_deleted: ConversationSupervisionMessage.where(conversation_supervision_session_id: session_ids).delete_all,
        snapshots_deleted: ConversationSupervisionSnapshot.where(conversation_supervision_session_id: session_ids).delete_all,
        sessions_deleted: ConversationSupervisionSession.where(id: session_ids).delete_all,
      }
    end

    def stale_session_ids
      ConversationSupervisionSession
        .where(lifecycle_state: "closed")
        .where("closed_at < ?", cutoff)
        .order(:closed_at, :id)
        .limit(batch_size)
        .pluck(:id)
    end
  end
end
