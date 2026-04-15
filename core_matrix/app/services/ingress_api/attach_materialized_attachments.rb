module IngressAPI
  class AttachMaterializedAttachments
    def self.call(...)
      new(...).call
    end

    def initialize(message:, attachment_records:)
      @message = message
      @attachment_records = Array(attachment_records)
    end

    def call
      Attachments::CreateForMessage.call(
        message: @message,
        files: @attachment_records.map do |attachment_record|
          {
            io: attachment_record.fetch("io"),
            filename: attachment_record.fetch("filename"),
            content_type: attachment_record["content_type"],
            byte_size: attachment_record["byte_size"],
            identify: false,
            metadata: {
              "source_file_id" => attachment_record["file_id"],
              "transport_metadata" => attachment_record["transport_metadata"],
            }.compact,
          }
        end,
        source_kind: "channel_ingress"
      )
    end
  end
end
