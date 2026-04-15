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
      @attachment_records.each do |attachment_record|
        io = attachment_record.fetch("io")
        io.rewind if io.respond_to?(:rewind)

        attachment = MessageAttachment.new(
          installation: @message.installation,
          conversation: @message.conversation,
          message: @message
        )
        attachment.file.attach(
          io: io,
          filename: attachment_record.fetch("filename"),
          content_type: attachment_record["content_type"],
          metadata: {
            "source_file_id" => attachment_record["file_id"],
            "transport_metadata" => attachment_record["transport_metadata"]
          }.compact,
          identify: false
        )
        attachment.save!
      end
    end
  end
end
