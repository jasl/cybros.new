module Attachments
  class MaterializeRefs
    def self.call(...)
      new(...).call
    end

    def initialize(message:, refs:)
      @message = message
      @refs = Array(refs)
    end

    def call
      ApplicationRecord.transaction do
        @refs.map do |ref|
          validate_ref!(ref)
          duplicated_blob = duplicate_blob(ref)

          attachment = MessageAttachment.new(
            installation: @message.installation,
            conversation: @message.conversation,
            message: @message,
            origin_attachment: ref
          )
          attachment.file.attach(duplicated_blob)
          attachment.save!
          attachment
        end
      end
    end

    private

    def duplicate_blob(ref)
      ref.file.blob.open do |source_io|
        return ActiveStorage::Blob.create_and_upload!(
          io: source_io,
          filename: ref.file.filename.to_s,
          content_type: ref.file.content_type,
          metadata: ref.file.blob.metadata,
          service_name: ref.file.blob.service_name
        )
      end
    end

    def validate_ref!(ref)
      raise ArgumentError, "refs must be message attachments" unless ref.is_a?(MessageAttachment)
      raise ArgumentError, "ref attachments must belong to the same installation as the target message" unless ref.installation_id == @message.installation_id
      raise ArgumentError, "ref attachments must have an attached file" unless ref.file.attached?
    end
  end
end
