module ConversationExports
  class CreateRequest
    DEFAULT_TTL = 24.hours

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, user:, expires_at: Time.current + DEFAULT_TTL)
      @conversation = conversation
      @user = user
      @expires_at = expires_at
    end

    def call
      request = ConversationExportRequest.create!(
        installation: @conversation.installation,
        workspace: @conversation.workspace,
        conversation: @conversation,
        user: @user,
        lifecycle_state: "queued",
        queued_at: Time.current,
        expires_at: @expires_at,
        request_payload: {
          "bundle_kind" => ConversationExports::BuildConversationPayload::BUNDLE_KIND,
          "bundle_version" => ConversationExports::BuildConversationPayload::BUNDLE_VERSION,
        }
      )

      ConversationExports::ExecuteRequestJob.perform_later(request.public_id)
      ConversationExports::ExpireRequestJob.set(wait_until: request.expires_at).perform_later(request.public_id)
      request
    end
  end
end
