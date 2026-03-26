module Conversations
  module WorkQuiescenceGuard
    private

    def ensure_mainline_stop_barrier_clear!(conversation, stage:)
      barrier = barrier_for(conversation)

      raise_invalid!(conversation, :base, "must not have active turns before #{stage}") if barrier[:active_turn_count].positive?
      raise_invalid!(conversation, :base, "must not have active workflow runs before #{stage}") if barrier[:active_workflow_count].positive?
      raise_invalid!(conversation, :base, "must not have active agent task execution before #{stage}") if barrier[:active_agent_task_count].positive?
      raise_invalid!(conversation, :base, "must not have open blocking human interaction before #{stage}") if barrier[:open_blocking_interaction_count].positive?
      raise_invalid!(conversation, :base, "must not have active turn-command process execution before #{stage}") if barrier[:running_turn_command_count].positive?
      raise_invalid!(conversation, :base, "must not have active subagent execution before #{stage}") if barrier[:running_subagent_count].positive?
    end

    def ensure_conversation_quiescent!(conversation, stage:)
      barrier = barrier_for(conversation)

      raise_invalid!(conversation, :base, "must not have queued turns before #{stage}") if barrier[:queued_turn_count].positive?
      ensure_mainline_stop_barrier_clear!(conversation, stage: stage)
      raise_invalid!(conversation, :base, "must not have active execution leases before #{stage}") if barrier[:active_execution_lease_count].positive?
      raise_invalid!(conversation, :base, "must not have open human interaction before #{stage}") if barrier[:open_interaction_count].positive?
      raise_invalid!(conversation, :base, "must not have active process execution before #{stage}") if barrier[:running_process_count].positive?
      raise_invalid!(conversation, :base, "must not have active subagent execution before #{stage}") if barrier[:running_subagent_count].positive?
    end

    def barrier_for(conversation)
      Conversations::WorkBarrierQuery.call(conversation: conversation)
    end
  end
end
