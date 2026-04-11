module AgentSnapshots
  class RebindTurn
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, recovery_target:)
      @turn = turn
      @conversation = turn.conversation
      @recovery_target = recovery_target
    end

    def call
      raise ArgumentError, "recovery target must require rebinding" unless @recovery_target.rebind_turn?
      validate_schedulable!

      ApplicationRecord.transaction do
        @turn.update!(
          agent_snapshot: @recovery_target.agent_snapshot,
          pinned_agent_snapshot_fingerprint: @recovery_target.agent_snapshot.fingerprint,
          resolved_model_selection_snapshot: @recovery_target.resolved_model_selection_snapshot
        )
        Workflows::BuildExecutionSnapshot.call(turn: @turn.reload)
      end

      @turn
    end

    private

    def validate_schedulable!
      return if resolved_agent_snapshot.eligible_for_scheduling?

      @turn.errors.add(:agent_snapshot, "must remain eligible for scheduling to continue paused work")
      raise ActiveRecord::RecordInvalid, @turn
    end

    def resolved_agent_snapshot
      @resolved_agent_snapshot ||= AgentSnapshot.find(@recovery_target.agent_snapshot.id)
    end
  end
end
