module Workflows
  class ResumeBlockedStepJob < ApplicationJob
    queue_as :workflow_resume

    def perform(workflow_run_id, expected_waiting_since_at_iso8601: nil)
      workflow_run = WorkflowRun.find_by_public_id!(workflow_run_id)
      return unless workflow_run.waiting?
      return unless workflow_run.blocking_resource_type == "WorkflowNode"
      return unless waiting_snapshot_matches?(workflow_run, expected_waiting_since_at_iso8601)

      Workflows::ResumeBlockedStep.call(workflow_run: workflow_run)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      nil
    end

    private

    def waiting_snapshot_matches?(workflow_run, expected_waiting_since_at_iso8601)
      return true if expected_waiting_since_at_iso8601.blank?

      workflow_run.waiting_since_at&.utc&.iso8601(6) == Time.iso8601(expected_waiting_since_at_iso8601).utc.iso8601(6)
    rescue ArgumentError
      false
    end
  end
end
