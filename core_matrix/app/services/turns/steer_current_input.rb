module Turns
  class SteerCurrentInput
    def self.call(...)
      new(...).call
    end

    def initialize(
      turn:,
      content:,
      policy_mode: nil,
      expected_turn_id: nil,
      origin_payload: nil,
      source_ref_type: nil,
      source_ref_id: nil
    )
      @turn = turn
      @content = content
      @policy_mode = policy_mode
      @expected_turn_id = expected_turn_id
      @origin_payload = origin_payload
      @source_ref_type = source_ref_type
      @source_ref_id = source_ref_id
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
        validate_expected_turn_id!(turn)
        if !paused_turn_resume_guidance?(turn) && side_effect_boundary_crossed?(turn)
          return Workflows::Scheduler.apply_during_generation_policy(
            turn: turn,
            content: @content,
            policy_mode: effective_policy_mode(turn),
            origin_kind: turn.origin_kind,
            origin_payload: resolved_origin_payload(turn),
            source_ref_type: resolved_source_ref_type(turn),
            source_ref_id: resolved_source_ref_id(turn)
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

        Turns::PersistSelectionState.call(turn: turn, selected_input_message: message)
        Conversations::RefreshLatestTurnAnchors.call(
          conversation: turn.conversation,
          turn: turn,
          message: message,
          activity_at: message.created_at
        )
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

      WorkflowNode.where(workflow_run: workflow_run, transcript_side_effect_committed: true).exists?
    end

    def paused_turn_resume_guidance?(turn)
      turn.workflow_run&.paused_turn?
    end

    def effective_policy_mode(turn)
      frozen_policy_mode = turn.during_generation_input_policy.presence || turn.conversation.during_generation_input_policy
      return frozen_policy_mode if @policy_mode.blank?
      return frozen_policy_mode if @policy_mode.to_s == frozen_policy_mode

      raise_invalid!(turn, :base, "must match the frozen during-generation input policy")
    end

    def validate_expected_turn_id!(turn)
      return if @expected_turn_id.blank?
      return if @expected_turn_id.to_s == turn.public_id

      raise_invalid!(turn, :base, "must match the active turn public id")
    end

    def resolved_origin_payload(turn)
      values = @origin_payload.respond_to?(:to_unsafe_h) ? @origin_payload.to_unsafe_h : @origin_payload
      values = turn.origin_payload if values.blank?
      raise ArgumentError, "origin_payload must be a hash" unless values.is_a?(Hash)

      values.deep_stringify_keys
    end

    def resolved_source_ref_type(turn)
      @source_ref_type.presence || turn.source_ref_type
    end

    def resolved_source_ref_id(turn)
      @source_ref_id.presence || turn.source_ref_id
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
