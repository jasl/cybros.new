module ConversationExports
  class ExecuteRequestJob < ApplicationJob
    queue_as :maintenance

    def perform(request_public_id)
      request = ConversationExportRequest.find_by_public_id!(request_public_id)
      return if request.succeeded? || request.expired?

      ConversationExports::ExecuteRequest.call(request: request)
    end
  end
end
