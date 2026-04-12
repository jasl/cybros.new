module ExecutionIdentityRecovery
  class RebindTurn
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, recovery_target:)
      @turn = turn
      @recovery_target = recovery_target
    end

    def call
      raise ArgumentError, "recovery target must require rebinding" unless @recovery_target.rebind_turn?
      validate_schedulable!

      ApplicationRecord.transaction do
        @turn.update!(
          agent_definition_version: @recovery_target.agent_definition_version,
          pinned_agent_definition_fingerprint: @recovery_target.agent_definition_version.definition_fingerprint,
          resolved_model_selection_snapshot: @recovery_target.resolved_model_selection_snapshot
        )
        Workflows::BuildExecutionSnapshot.call(turn: @turn.reload)
      end

      @turn
    end

    private

    def validate_schedulable!
      return if resolved_agent_definition_version.eligible_for_scheduling?

      @turn.errors.add(:agent_definition_version, "must remain eligible for scheduling to continue paused work")
      raise ActiveRecord::RecordInvalid, @turn
    end

    def resolved_agent_definition_version
      @resolved_agent_definition_version ||= AgentDefinitionVersion.find(@recovery_target.agent_definition_version.id)
    end
  end
end
