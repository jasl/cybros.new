module Conversations
  class ValidateTimelineSuffixSupersession
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turn:, record: turn)
      @conversation = conversation
      @turn = turn
      @record = record
    end

    def call
      raise_invalid!(:conversation, "must belong to the target conversation") unless @turn.conversation_id == @conversation.id

      barrier = Conversations::BlockerSnapshotQuery.call(
        conversation: @conversation,
        turns: suffix_turn_scope
      ).work_barrier

      raise_invalid!(:base, "must not roll back the timeline while later queued turns remain") if barrier[:queued_turn_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later active turns remain") if barrier[:active_turn_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later workflow runs remain active") if barrier[:active_workflow_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later queued agent tasks remain") if barrier[:queued_agent_task_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later agent tasks remain active") if barrier[:active_agent_task_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later human interactions remain open") if barrier[:open_interaction_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later process execution remains active") if barrier[:running_process_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later subagent execution remains active") if barrier[:running_subagent_count].positive?
      raise_invalid!(:base, "must not roll back the timeline while later execution leases remain active") if barrier[:active_execution_lease_count].positive?

      @turn
    end

    private

    def suffix_turn_scope
      @conversation.turns.where("sequence > ?", @turn.sequence)
    end

    def raise_invalid!(attribute, message)
      @record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
