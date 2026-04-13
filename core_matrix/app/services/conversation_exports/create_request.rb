module ConversationExports
  class CreateRequest
    DEFAULT_TTL = 24.hours

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, user:, request_kind: "conversation_export", expires_at: Time.current + DEFAULT_TTL)
      @conversation = conversation
      @user = user
      @request_kind = request_kind.to_s
      @expires_at = expires_at
    end

    def call
      request = ConversationExportRequest.create!(
        installation: @conversation.installation,
        workspace: @conversation.workspace,
        conversation: @conversation,
        user: @user,
        request_kind: @request_kind,
        lifecycle_state: "queued",
        queued_at: Time.current,
        expires_at: @expires_at,
        request_payload: request_payload
      )

      ConversationExports::ExecuteRequestJob.perform_later(request.public_id)
      ConversationExports::ExpireRequestJob.set(wait_until: request.expires_at).perform_later(request.public_id)
      request
    end

    private

    def request_payload
      if @request_kind == "debug_export"
        {
          "bundle_kind" => ConversationDebugExports::BuildPayload::BUNDLE_KIND,
          "bundle_version" => ConversationDebugExports::BuildPayload::BUNDLE_VERSION,
        }
      else
        {
          "bundle_kind" => ConversationExports::BuildConversationPayload::BUNDLE_KIND,
          "bundle_version" => ConversationExports::BuildConversationPayload::BUNDLE_VERSION,
        }
      end
    end
  end
end
