module HumanInteractions
  module LockedContext
    private

    def with_locked_workflow_context(workflow_node_id)
      ApplicationRecord.transaction do
        workflow_node = WorkflowNode.find(workflow_node_id)
        workflow_run = WorkflowRun.find(workflow_node.workflow_run_id)
        conversation = Conversation.find(workflow_run.conversation_id)

        conversation.with_lock do
          workflow_run.with_lock do
            yield workflow_node.reload, workflow_run.reload, conversation.reload
          end
        end
      end
    end

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
