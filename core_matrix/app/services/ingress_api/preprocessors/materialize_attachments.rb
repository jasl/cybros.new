module IngressAPI
  module Preprocessors
    class MaterializeAttachments
      DEFAULT_MAX_BYTES = 100.megabytes
      DEFAULT_MAX_COUNT = 10

      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("materialize_attachments")
        attachment_descriptors = Array(@context.envelope.attachments)
        if attachment_descriptors.length > attachment_max_count
          @context.result = rejected_result("attachment_count_exceeded")
          return @context
        end

        oversize_descriptor = attachment_descriptors.find { |descriptor| known_byte_size(descriptor) > attachment_max_bytes }
        if oversize_descriptor.present?
          @context.result = rejected_result("attachment_too_large")
          return @context
        end

        @context.attachment_records = attachment_descriptors.map do |attachment_descriptor|
          materialize_attachment(attachment_descriptor)
        end
        oversize_record = @context.attachment_records.find { |record| record.fetch("byte_size", 0).to_i > attachment_max_bytes }
        if oversize_record.present?
          @context.result = rejected_result("attachment_too_large")
        end
        @context
      end

      private

      def attachment_max_bytes
        @context.channel_connector.config_payload.dig("attachment_policy", "max_bytes").to_i.then do |value|
          value.positive? ? value : DEFAULT_MAX_BYTES
        end
      end

      def attachment_max_count
        @context.channel_connector.config_payload.dig("attachment_policy", "max_count").to_i.then do |value|
          value.positive? ? value : DEFAULT_MAX_COUNT
        end
      end

      def known_byte_size(attachment_descriptor)
        attachment_descriptor.fetch("byte_size", 0).to_i
      end

      def materialize_attachment(attachment_descriptor)
        case @context.envelope.platform
        when "telegram"
          IngressAPI::Telegram::DownloadAttachment.call(
            client: telegram_client,
            attachment_descriptor: attachment_descriptor,
            bot_token: IngressAPI::Telegram::Client.bot_token_for(@context.channel_connector)
          )
        else
          attachment_descriptor
        end
      end

      def telegram_client
        @telegram_client ||= IngressAPI::Telegram::Client.for_channel_connector(@context.channel_connector)
      end

      def rejected_result(reason)
        IngressAPI::Result.rejected(
          rejection_reason: reason,
          trace: @context.pipeline_trace,
          envelope: @context.envelope,
          conversation: @context.conversation,
          channel_session: @context.channel_session,
          request_metadata: @context.request_metadata
        )
      end
    end
  end
end
