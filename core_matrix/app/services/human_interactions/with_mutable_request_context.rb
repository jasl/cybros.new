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

        Workflows::WithMutableWorkflowContext.call(
          workflow_run: workflow_run,
          record: request,
          retained_message: @retained_message,
          active_message: @active_message,
          closing_message: @closing_message
        ) do |conversation, current_workflow_run, _turn|
          request.with_lock do
            yield request.reload, current_workflow_run, conversation
          end
        end
      end
    end
  end
end
