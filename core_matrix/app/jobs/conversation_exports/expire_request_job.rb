module ConversationExports
  class ExpireRequestJob < ApplicationJob
    queue_as :maintenance

    def perform(request_public_id)
      request = ConversationExportRequest.find_by_public_id!(request_public_id)
      return if request.expired?
      return unless request.succeeded?
      return if request.expires_at.future?

      request.bundle_file.purge if request.bundle_file.attached?
      request.update!(
        lifecycle_state: "expired",
        finished_at: request.finished_at || Time.current
      )
    end
  end
end
