module Workflows
  class ResumeBlockedStepJob < ApplicationJob
    queue_as :workflow_resume

    def perform(workflow_run_id)
      workflow_run = WorkflowRun.find_by_public_id!(workflow_run_id)
      return unless workflow_run.waiting?
      return unless workflow_run.blocking_resource_type == "WorkflowNode"

      Workflows::ResumeBlockedStep.call(workflow_run: workflow_run)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      nil
    end
  end
end
