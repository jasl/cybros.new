module Conversations
  module WorkQuiescenceGuard
    private

    def ensure_conversation_quiescent!(conversation, stage:)
      raise_invalid!(conversation, :base, "must not have queued turns before #{stage}") if Turn.where(conversation: conversation, lifecycle_state: "queued").exists?
      raise_invalid!(conversation, :base, "must not have active turns before #{stage}") if conversation.active_turn_exists?
      raise_invalid!(conversation, :base, "must not have active workflow runs before #{stage}") if WorkflowRun.where(conversation: conversation, lifecycle_state: "active").exists?
      raise_invalid!(conversation, :base, "must not have active execution leases before #{stage}") if active_execution_leases?(conversation)
      raise_invalid!(conversation, :base, "must not have open human interaction before #{stage}") if open_human_interactions?(conversation)
      raise_invalid!(conversation, :base, "must not have active process execution before #{stage}") if running_processes?(conversation)
      raise_invalid!(conversation, :base, "must not have active subagent execution before #{stage}") if running_subagents?(conversation)
    end

    def active_execution_leases?(conversation)
      ExecutionLease.joins(:workflow_run).where(workflow_runs: { conversation_id: conversation.id }, released_at: nil).exists?
    end

    def open_human_interactions?(conversation)
      HumanInteractionRequest.where(conversation: conversation, lifecycle_state: "open").exists?
    end

    def running_processes?(conversation)
      ProcessRun.where(conversation: conversation, lifecycle_state: "running").exists?
    end

    def running_subagents?(conversation)
      SubagentRun.joins(:workflow_run).where(workflow_runs: { conversation_id: conversation.id }, lifecycle_state: "running").exists?
    end
  end
end
