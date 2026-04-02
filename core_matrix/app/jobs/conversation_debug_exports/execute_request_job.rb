module ConversationDebugExports
  class ExecuteRequestJob < ApplicationJob
    queue_as :maintenance

    def perform(request_public_id)
      request = ConversationDebugExportRequest.find_by_public_id!(request_public_id)
      return if request.succeeded? || request.expired?

      ConversationDebugExports::ExecuteRequest.call(request: request)
    end
  end
end
