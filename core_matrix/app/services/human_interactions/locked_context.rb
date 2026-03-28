module HumanInteractions
  module LockedContext
    private

    def with_locked_request_context(request_record)
      ApplicationRecord.transaction do
        request = request_record.class.find(request_record.id)
        workflow_run = WorkflowRun.find(request.workflow_run_id)
        conversation = Conversation.find(request.conversation_id)

        conversation.with_lock do
          workflow_run.with_lock do
            request.with_lock do
              yield request.reload, workflow_run.reload, conversation.reload
            end
          end
        end
      end
    end
  end
end
