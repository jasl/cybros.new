module Workflows
  class WithMutableWorkflowContext
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(
      workflow_run:,
      record: nil,
      retained_message:,
      active_message:,
      closing_message:
    )
      @workflow_run = workflow_run
      @record = record
      @retained_message = retained_message
      @active_message = active_message
      @closing_message = closing_message
    end

    def call
      Conversations::WithMutableStateLock.call(
        conversation: @workflow_run.conversation,
        record: @record || @workflow_run.conversation,
        retained_message: @retained_message,
        active_message: @active_message,
        closing_message: @closing_message
      ) do |conversation|
        Workflows::WithLockedWorkflowContext.call(workflow_run: @workflow_run) do |workflow_run, turn|
          yield conversation, workflow_run, turn
        end
      end
    end
  end
end
