module Turns
  class SteerCurrentInput
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, content:, policy_mode: nil)
      @turn = turn
      @content = content
      @policy_mode = policy_mode
    end

    def call
      Turns::WithTimelineMutationLock.call(
        turn: @turn,
        retained_message: "must be retained before steering current input",
        active_message: "must belong to an active conversation to steer current input",
        closing_message: "must not steer current input while close is in progress",
        interrupted_message: "must not steer current input after turn interruption"
      ) do |turn|
        raise_invalid!(turn, :lifecycle_state, "must be active to steer current input") unless turn.active?
        if side_effect_boundary_crossed?(turn)
          return Workflows::Scheduler.apply_during_generation_policy(
            turn: turn,
            content: @content,
            policy_mode: effective_policy_mode(turn)
          )
        end

        message = UserMessage.create!(
          installation: turn.installation,
          conversation: turn.conversation,
          turn: turn,
          role: "user",
          slot: "input",
          variant_index: turn.messages.where(slot: "input").maximum(:variant_index).to_i + 1,
          content: @content
        )

        turn.update!(selected_input_message: message)
        turn
      end
    end

    private

    def side_effect_boundary_crossed?(turn)
      turn.selected_output_message.present? || workflow_run_side_effect_nodes_exist?(turn)
    end

    def workflow_run_side_effect_nodes_exist?(turn)
      workflow_run = turn.workflow_run
      return false if workflow_run.blank?

      WorkflowNode.where(workflow_run: workflow_run).any? do |node|
        node.metadata["transcript_side_effect_committed"]
      end
    end

    def effective_policy_mode(turn)
      frozen_policy_mode = turn.during_generation_input_policy.presence || turn.conversation.during_generation_input_policy
      return frozen_policy_mode if @policy_mode.blank?
      return frozen_policy_mode if @policy_mode.to_s == frozen_policy_mode

      raise_invalid!(turn, :base, "must match the frozen during-generation input policy")
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
