module Conversations
  module WorkQuiescenceGuard
    private

    def ensure_mainline_stop_barrier_clear!(conversation, stage:)
      raise_invalid!(conversation, :base, "must not have active turns before #{stage}") if Turn.where(conversation: conversation, lifecycle_state: "active").exists?
      raise_invalid!(conversation, :base, "must not have active workflow runs before #{stage}") if WorkflowRun.where(conversation: conversation, lifecycle_state: "active").exists?
      raise_invalid!(conversation, :base, "must not have active agent task execution before #{stage}") if AgentTaskRun.where(conversation: conversation, lifecycle_state: "running").exists?
      raise_invalid!(conversation, :base, "must not have open blocking human interaction before #{stage}") if blocking_human_interactions?(conversation)
      raise_invalid!(conversation, :base, "must not have active turn-command process execution before #{stage}") if running_turn_command_processes?(conversation)
      raise_invalid!(conversation, :base, "must not have active subagent execution before #{stage}") if running_subagents?(conversation)
    end

    def ensure_conversation_quiescent!(conversation, stage:)
      raise_invalid!(conversation, :base, "must not have queued turns before #{stage}") if Turn.where(conversation: conversation, lifecycle_state: "queued").exists?
      ensure_mainline_stop_barrier_clear!(conversation, stage: stage)
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

    def blocking_human_interactions?(conversation)
      HumanInteractionRequest.where(conversation: conversation, lifecycle_state: "open", blocking: true).exists?
    end

    def running_processes?(conversation)
      ProcessRun.where(conversation: conversation, lifecycle_state: "running").exists?
    end

    def running_turn_command_processes?(conversation)
      ProcessRun.where(conversation: conversation, lifecycle_state: "running", kind: "turn_command").exists?
    end

    def running_subagents?(conversation)
      SubagentRun.joins(:workflow_run).where(workflow_runs: { conversation_id: conversation.id }, lifecycle_state: "running").exists?
    end
  end
end
