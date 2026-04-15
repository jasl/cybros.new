module IngressAPI
  module Middleware
    class CaptureRawPayload
      def self.call(...)
        new(...).call
      end

      def initialize(context:, raw_payload:)
        @context = context
        @raw_payload = raw_payload
      end

      def call
        @context.raw_payload = @raw_payload
        @context.append_trace("capture_raw_payload")
        @context
      end
    end
  end
end
