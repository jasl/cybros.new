module ConversationBundleImports
  class ExecuteRequest
    def self.call(...)
      new(...).call
    end

    def initialize(request:)
      @request = request
    end

    def call
      @request.update!(
        lifecycle_state: "running",
        started_at: Time.current
      )

      ApplicationRecord.transaction(requires_new: true) do
        parsed_bundle = ConversationBundleImports::ParseUpload.call(request: @request)
        ConversationBundleImports::ValidateManifest.call(parsed_bundle: parsed_bundle)
        imported_conversation = ConversationBundleImports::RehydrateConversation.call(
          request: @request,
          parsed_bundle: parsed_bundle
        )

        @request.update!(
          lifecycle_state: "succeeded",
          imported_conversation: imported_conversation,
          finished_at: Time.current,
          result_payload: {
            "bundle_kind" => parsed_bundle.dig("manifest", "bundle_kind"),
            "bundle_version" => parsed_bundle.dig("manifest", "bundle_version"),
            "imported_conversation_id" => imported_conversation.public_id,
            "message_count" => parsed_bundle.dig("manifest", "message_count"),
            "attachment_count" => parsed_bundle.dig("manifest", "attachment_count"),
          }
        )
      end
    rescue StandardError => error
      @request.reload
      @request.update!(
        lifecycle_state: "failed",
        finished_at: Time.current,
        failure_payload: {
          "error_class" => error.class.name,
          "message" => error.message,
        }
      )
      raise
    end
  end
end
