module ConversationDiagnostics
  class ResolveSnapshotStatus
    Result = Struct.new(
      :status,
      :reason,
      :conversation_snapshot,
      :turn_snapshot_count,
      keyword_init: true
    ) do
      def ready?
        status == "ready"
      end

      def stale?
        status == "stale"
      end

      def pending?
        status == "pending"
      end

      def turn_lifecycle_drift?
        reason == "turn_lifecycle_drift"
      end
    end

    FACT_WATERMARK_SCOPES = [
      ->(conversation_id) { UsageEvent.where(conversation_id: conversation_id).maximum(:occurred_at) },
      ->(conversation_id) { WorkflowRun.where(conversation_id: conversation_id).maximum(:updated_at) },
      ->(conversation_id) { AgentTaskRun.where(conversation_id: conversation_id).maximum(:updated_at) },
      ->(conversation_id) { ToolInvocation.where(conversation_id: conversation_id).maximum(:updated_at) },
      ->(conversation_id) { CommandRun.where(conversation_id: conversation_id).maximum(:updated_at) },
      ->(conversation_id) { ProcessRun.where(conversation_id: conversation_id).maximum(:updated_at) },
      ->(conversation_id) { SubagentConnection.where(owner_conversation_id: conversation_id).maximum(:updated_at) },
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation_snapshot = ConversationDiagnosticsSnapshot.find_by(conversation: @conversation)
      turn_count = Turn.where(conversation: @conversation).count
      turn_snapshot_count = TurnDiagnosticsSnapshot.where(conversation: @conversation).count

      return pending_result(conversation_snapshot, turn_snapshot_count) if conversation_snapshot.blank?
      return pending_result(conversation_snapshot, turn_snapshot_count) if turn_snapshot_count < turn_count
      if turn_lifecycle_drift?
        return Result.new(
          status: "stale",
          reason: "turn_lifecycle_drift",
          conversation_snapshot: conversation_snapshot,
          turn_snapshot_count: turn_snapshot_count
        )
      end

      if conversation_snapshot.updated_at < source_watermark
        return Result.new(
          status: "stale",
          reason: nil,
          conversation_snapshot: conversation_snapshot,
          turn_snapshot_count: turn_snapshot_count
        )
      end

      Result.new(
        status: "ready",
        reason: nil,
        conversation_snapshot: conversation_snapshot,
        turn_snapshot_count: turn_snapshot_count
      )
    end

    private

    def pending_result(conversation_snapshot, turn_snapshot_count)
      Result.new(
        status: "pending",
        reason: nil,
        conversation_snapshot: conversation_snapshot,
        turn_snapshot_count: turn_snapshot_count
      )
    end

    def turn_lifecycle_drift?
      TurnDiagnosticsSnapshot
        .joins(:turn)
        .where(conversation: @conversation)
        .where("turn_diagnostics_snapshots.lifecycle_state <> turns.lifecycle_state")
        .exists?
    end

    def source_watermark
      @source_watermark ||= begin
        watermarks = [
          @conversation.updated_at,
          Turn.where(conversation: @conversation).maximum(:updated_at),
        ]
        FACT_WATERMARK_SCOPES.each do |scope|
          watermarks << scope.call(@conversation.id)
        end
        watermarks.compact.max || @conversation.updated_at
      end
    end
  end
end
