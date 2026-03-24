require "stringio"

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

          attachment = MessageAttachment.new(
            installation: @message.installation,
            conversation: @message.conversation,
            message: @message,
            origin_attachment: ref
          )
          attachment.file.attach(
            io: StringIO.new(ref.file.download),
            filename: ref.file.filename.to_s,
            content_type: ref.file.content_type
          )
          attachment.save!
          attachment
        end
      end
    end

    private

    def validate_ref!(ref)
      raise ArgumentError, "refs must be message attachments" unless ref.is_a?(MessageAttachment)
      raise ArgumentError, "ref attachments must belong to the same installation as the target message" unless ref.installation_id == @message.installation_id
      raise ArgumentError, "ref attachments must have an attached file" unless ref.file.attached?
    end
  end
end
