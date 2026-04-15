module IngressAPI
  module Middleware
    class DeduplicateInbound
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("deduplicate_inbound")
        return @context if @context.envelope.blank?

        duplicate = ChannelInboundMessage.exists?(
          channel_connector_id: @context.channel_connector.id,
          external_event_key: @context.envelope.external_event_key
        )
        return @context unless duplicate

        @context.result = IngressAPI::Result.duplicate(
          trace: @context.pipeline_trace,
          envelope: @context.envelope,
          channel_session: @context.channel_session,
          request_metadata: @context.request_metadata
        )
        @context
      end
    end
  end
end
