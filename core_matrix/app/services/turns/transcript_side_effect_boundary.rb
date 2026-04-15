module Turns
  class TranscriptSideEffectBoundary
    def self.crossed?(turn)
      return false if turn.blank?
      return true if turn.selected_output_message.present?

      workflow_run = turn.workflow_run
      return false if workflow_run.blank?

      WorkflowNode.where(workflow_run: workflow_run, transcript_side_effect_committed: true).exists?
    end
  end
end
