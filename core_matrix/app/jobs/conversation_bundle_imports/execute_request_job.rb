module ConversationBundleImports
  class ExecuteRequestJob < ApplicationJob
    queue_as :maintenance

    def perform(request_public_id)
      request = ConversationBundleImportRequest.find_by_public_id!(request_public_id)
      return if request.succeeded? || request.failed?

      ConversationBundleImports::ExecuteRequest.call(request: request)
    end
  end
end
