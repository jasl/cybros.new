module Turns
  class SteerCurrentInput
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, content:, policy_mode: "queue")
      @turn = turn
      @content = content
      @policy_mode = policy_mode
    end

    def call
      raise_invalid!(@turn, :lifecycle_state, "must be active to steer current input") unless @turn.active?
      if side_effect_boundary_crossed?
        return Workflows::Scheduler.apply_during_generation_policy(
          turn: @turn,
          content: @content,
          policy_mode: @policy_mode
        )
      end

      @turn.with_lock do
        @turn.reload
        raise_invalid!(@turn, :lifecycle_state, "must be active to steer current input") unless @turn.active?

        message = UserMessage.create!(
          installation: @turn.installation,
          conversation: @turn.conversation,
          turn: @turn,
          role: "user",
          slot: "input",
          variant_index: @turn.messages.where(slot: "input").maximum(:variant_index).to_i + 1,
          content: @content
        )

        @turn.update!(selected_input_message: message)
        @turn
      end
    end

    private

    def side_effect_boundary_crossed?
      @turn.selected_output_message.present? || workflow_run_side_effect_nodes_exist?
    end

    def workflow_run_side_effect_nodes_exist?
      workflow_run = @turn.workflow_run
      return false if workflow_run.blank?

      WorkflowNode.where(workflow_run: workflow_run).any? do |node|
        node.metadata["transcript_side_effect_committed"]
      end
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
