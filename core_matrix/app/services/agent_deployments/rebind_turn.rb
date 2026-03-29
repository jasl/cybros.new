module AgentDeployments
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
        @conversation.update!(agent_deployment: @recovery_target.agent_deployment)
        @turn.update!(
          agent_deployment: @recovery_target.agent_deployment,
          pinned_deployment_fingerprint: @recovery_target.agent_deployment.fingerprint,
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
      return if @recovery_target.agent_deployment.eligible_for_scheduling?

      @turn.errors.add(:agent_deployment, "must remain eligible for scheduling to continue paused work")
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
