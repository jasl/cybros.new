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

      Turns::WithTimelineMutationLock.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      ) do |locked_turn|
        raise_invalid!(locked_turn, :lifecycle_state, "must be completed to rerun output") unless locked_turn.completed?
        if locked_turn.tail_in_active_timeline? && locked_turn.selected_output_message_id == @message.id && @message.reload.fork_point?
          raise_invalid!(locked_turn, :base, "cannot rewrite a fork-point output")
        end

        if locked_turn.tail_in_active_timeline? && locked_turn.selected_output_message_id == @message.id
          return rerun_in_place(locked_turn)
        end

        rerun_in_branch(locked_turn)
      end
    end

    private

    def rerun_in_place(turn)
      raise_invalid!(turn, :lifecycle_state, "must be completed to rerun output") unless turn.completed?
      raise_invalid!(turn, :selected_output_message, "must match the rerun target") unless turn.selected_output_message_id == @message.id
      raise_invalid!(turn, :base, "must target the selected tail output") unless turn.tail_in_active_timeline?
      raise_invalid!(turn, :base, "cannot rewrite a fork-point output") if @message.reload.fork_point?

      source_input_message = source_input_message_for_replay!(turn)
      rerun_output = Turns::CreateOutputVariant.call(
        turn: turn,
        content: @content,
        source_input_message: source_input_message
      )

      turn.update!(
        selected_output_message: rerun_output,
        lifecycle_state: "active"
      )
      turn.conversation.refresh_latest_anchors!(activity_at: rerun_output.created_at)
      turn
    end

    def rerun_in_branch(turn)
      source_input_message = source_input_message_for_replay!(turn)
      branch = Conversations::CreateBranch.call(
        parent: turn.conversation,
        historical_anchor_message_id: @message.id
      )
      rerun_turn = Turns::StartUserTurn.call(
        conversation: branch,
        content: source_input_message.content,
        resolved_config_snapshot: turn.resolved_config_snapshot,
        resolved_model_selection_snapshot: turn.resolved_model_selection_snapshot
      )
      rerun_output = Turns::CreateOutputVariant.call(
        turn: rerun_turn,
        content: @content,
        source_input_message: rerun_turn.selected_input_message
      )

      rerun_turn.update!(selected_output_message: rerun_output)
      rerun_turn.conversation.refresh_latest_anchors!(activity_at: rerun_output.created_at)
      rerun_turn
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end

    def source_input_message_for_replay!(turn)
      @message.reload.source_input_message ||
        raise_invalid!(turn, :selected_output_message, "must carry source input provenance")
    end
  end
end
