module Conversations
  class ValidateQuiescence
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, stage:, mainline_only:, record: conversation)
      @conversation = conversation
      @stage = stage
      @mainline_only = mainline_only
      @record = record
    end

    def call
      ensure_owned_subagent_sessions_closed!

      raise_invalid!(:base, "must not have active turns before #{@stage}") if barrier[:active_turn_count].positive?
      raise_invalid!(:base, "must not have active workflow runs before #{@stage}") if barrier[:active_workflow_count].positive?
      raise_invalid!(:base, "must not have active agent task execution before #{@stage}") if barrier[:active_agent_task_count].positive?
      raise_invalid!(:base, "must not have open blocking human interaction before #{@stage}") if barrier[:open_blocking_interaction_count].positive?
      raise_invalid!(:base, "must not have active subagent execution before #{@stage}") if barrier[:running_subagent_count].positive?

      unless @mainline_only
        raise_invalid!(:base, "must not have queued turns before #{@stage}") if barrier[:queued_turn_count].positive?
        raise_invalid!(:base, "must not have active execution leases before #{@stage}") if barrier[:active_execution_lease_count].positive?
        raise_invalid!(:base, "must not have open human interaction before #{@stage}") if barrier[:open_interaction_count].positive?
        raise_invalid!(:base, "must not have active process execution before #{@stage}") if barrier[:running_process_count].positive?
      end

      @conversation
    end

    private

    def barrier
      @barrier ||= Conversations::BlockerSnapshotQuery.call(conversation: @conversation).work_barrier
    end

    def ensure_owned_subagent_sessions_closed!
      session_ids = SubagentSessions::OwnedTree.session_ids_for(owner_conversation: @conversation)
      return if session_ids.empty?

      pending_sessions = SubagentSession
        .where(id: session_ids)
        .merge(SubagentSession.close_pending_or_open)
      return unless pending_sessions.exists?

      qualifier = @stage == "archival" ? "open" : "open or close-pending"
      raise_invalid!(:base, "must not have #{qualifier} subagent sessions before #{@stage}")
    end

    def raise_invalid!(attribute, message)
      @record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
