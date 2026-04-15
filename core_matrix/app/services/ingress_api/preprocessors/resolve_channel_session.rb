module IngressAPI
  module Preprocessors
    class ResolveChannelSession
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("resolve_channel_session")
        normalized_thread_key = @context.envelope.thread_key.to_s.presence || ""

        @context.channel_session = ChannelSession.find_by(
          installation_id: @context.ingress_binding.installation_id,
          channel_connector_id: @context.channel_connector.id,
          peer_kind: @context.envelope.peer_kind,
          peer_id: @context.envelope.peer_id,
          normalized_thread_key: normalized_thread_key
        )

        if @context.channel_session.blank?
          @context.result = IngressAPI::Result.rejected(
            rejection_reason: "channel_session_not_found",
            trace: @context.pipeline_trace,
            envelope: @context.envelope,
            request_metadata: @context.request_metadata
          )
        end

        @context
      end
    end
  end
end
