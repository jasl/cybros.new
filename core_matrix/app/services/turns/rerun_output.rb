module Turns
  class RerunOutput
    def self.call(...)
      new(...).call
    end

    def initialize(message:, content:)
      @message = message
      @content = content
    end

    def call
      turn = @message.turn

      raise_invalid!(turn, :lifecycle_state, "must be completed to rerun output") unless turn.completed?
      if turn.tail_in_active_timeline? && turn.selected_output_message_id == @message.id && @message.fork_point?
        raise_invalid!(turn, :base, "cannot rewrite a fork-point output")
      end

      if turn.tail_in_active_timeline? && turn.selected_output_message_id == @message.id
        return rerun_in_place(turn)
      end

      rerun_in_branch(turn)
    end

    private

    def rerun_in_place(turn)
      turn.with_lock do
        turn.reload
        raise_invalid!(turn, :lifecycle_state, "must be completed to rerun output") unless turn.completed?
        raise_invalid!(turn, :selected_output_message, "must match the rerun target") unless turn.selected_output_message_id == @message.id
        raise_invalid!(turn, :base, "must target the selected tail output") unless turn.tail_in_active_timeline?
        raise_invalid!(turn, :base, "cannot rewrite a fork-point output") if @message.reload.fork_point?

        rerun_output = AgentMessage.create!(
          installation: turn.installation,
          conversation: turn.conversation,
          turn: turn,
          role: "agent",
          slot: "output",
          variant_index: turn.messages.where(slot: "output").maximum(:variant_index).to_i + 1,
          content: @content
        )

        turn.update!(
          selected_output_message: rerun_output,
          lifecycle_state: "active"
        )
        turn
      end
    end

    def rerun_in_branch(turn)
      branch = Conversations::CreateBranch.call(
        parent: turn.conversation,
        historical_anchor_message_id: @message.id
      )
      rerun_turn = Turns::StartUserTurn.call(
        conversation: branch,
        content: turn.selected_input_message.content,
        agent_deployment: turn.agent_deployment,
        resolved_config_snapshot: turn.resolved_config_snapshot,
        resolved_model_selection_snapshot: turn.resolved_model_selection_snapshot
      )
      rerun_output = AgentMessage.create!(
        installation: rerun_turn.installation,
        conversation: rerun_turn.conversation,
        turn: rerun_turn,
        role: "agent",
        slot: "output",
        variant_index: 0,
        content: @content
      )

      rerun_turn.update!(selected_output_message: rerun_output)
      rerun_turn
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
