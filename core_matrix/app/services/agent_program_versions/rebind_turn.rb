module AgentProgramVersions
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
          agent_program_version: @recovery_target.agent_program_version,
          pinned_program_version_fingerprint: @recovery_target.agent_program_version.fingerprint,
          resolved_model_selection_snapshot: @recovery_target.resolved_model_selection_snapshot
        )
        @turn.update!(
          execution_snapshot_payload: Workflows::BuildExecutionSnapshot.call(turn: @turn).to_h
        )
      end

      @turn
    end

    private

    def validate_schedulable!
      return if resolved_agent_program_version.eligible_for_scheduling?

      @turn.errors.add(:agent_program_version, "must remain eligible for scheduling to continue paused work")
      raise ActiveRecord::RecordInvalid, @turn
    end

    def resolved_agent_program_version
      @resolved_agent_program_version ||= AgentProgramVersion.find(@recovery_target.agent_program_version.id)
    end
  end
end
