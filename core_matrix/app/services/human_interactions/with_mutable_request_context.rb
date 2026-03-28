module HumanInteractions
  class WithMutableRequestContext
    include HumanInteractions::LockedContext

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
      with_locked_request_context(@request) do |request, workflow_run, conversation|
        Conversations::ValidateMutableState.call(
          conversation: conversation,
          record: request,
          retained_message: @retained_message,
          active_message: @active_message,
          closing_message: @closing_message
        )

        yield request, workflow_run, conversation
      end
    end
  end
end
