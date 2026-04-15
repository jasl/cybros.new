module IngressAPI
  module Middleware
    class VerifyRequest
      def self.call(...)
        new(...).call
      end

      def initialize(context:, adapter:, raw_payload:, request_metadata:)
        @context = context
        @adapter = adapter
        @raw_payload = raw_payload
        @request_metadata = request_metadata
      end

      def call
        verified = @adapter.verify_request!(
          raw_payload: @raw_payload,
          request_metadata: @request_metadata
        )
        @context.ingress_binding = verified.fetch(:ingress_binding)
        @context.channel_connector = verified.fetch(:channel_connector)
        @context.append_trace("verify_request")
        @context
      end
    end
  end
end
