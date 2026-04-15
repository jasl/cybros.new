module IngressAPI
  module Preprocessors
    class MaterializeAttachments
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("materialize_attachments")
        @context.attachment_records ||= []
        @context
      end
    end
  end
end
