module ConversationDebugExports
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

      bundle = nil
      ApplicationRecord.transaction(requires_new: true) do
        bundle = ConversationDebugExports::WriteZipBundle.call(conversation: @request.conversation)

        @request.bundle_file.attach(
          io: bundle.fetch("io"),
          filename: bundle.fetch("filename"),
          content_type: bundle.fetch("content_type")
        )
        @request.update!(
          lifecycle_state: "succeeded",
          finished_at: Time.current,
          result_payload: {
            "bundle_kind" => bundle.dig("manifest", "bundle_kind"),
            "bundle_version" => bundle.dig("manifest", "bundle_version"),
            "message_count" => bundle.dig("manifest", "counts", "message_count"),
            "attachment_count" => bundle.dig("manifest", "attachment_count"),
            "workflow_run_count" => bundle.dig("manifest", "counts", "workflow_run_count"),
            "tool_invocation_count" => bundle.dig("manifest", "counts", "tool_invocation_count"),
            "usage_event_count" => bundle.dig("manifest", "counts", "usage_event_count"),
          }
        )
      end

      schedule_expiration!
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
    ensure
      bundle&.fetch("io")&.close!
    end

    private

    def schedule_expiration!
      if @request.expires_at <= Time.current
        ConversationDebugExports::ExpireRequestJob.perform_later(@request.public_id)
      else
        ConversationDebugExports::ExpireRequestJob.set(wait_until: @request.expires_at).perform_later(@request.public_id)
      end
    end
  end
end
