module HumanInteractions
  class WithMutableRequestContext
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(
      request:,
      retained_message: "must be retained before resolving human interaction",
      active_message: "must be active before resolving human interaction",
      closing_message: "must not resolve human interaction while close is in progress"
    )
      @request = request
      @retained_message = retained_message
      @active_message = active_message
      @closing_message = closing_message
    end

    def call
      ApplicationRecord.transaction do
        request = @request.class.find(@request.id)
        workflow_run = WorkflowRun.find(request.workflow_run_id)
        conversation = Conversation.find(request.conversation_id)

        conversation.with_lock do
          workflow_run.with_lock do
            request.with_lock do
              locked_request = request.reload
              locked_workflow_run = workflow_run.reload
              locked_conversation = conversation.reload

              Conversations::ValidateMutableState.call(
                conversation: locked_conversation,
                record: locked_request,
                retained_message: @retained_message,
                active_message: @active_message,
                closing_message: @closing_message
              )

              yield locked_request, locked_workflow_run, locked_conversation
            end
          end
        end
      end
    end
  end
end
