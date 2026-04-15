module IngressAPI
  module Preprocessors
    class ResolveDispatchDecision
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("resolve_dispatch_decision")
        @context.dispatch_decision = "new_turn"
        @context.origin_payload = {
          "platform" => @context.envelope.platform,
          "driver" => @context.envelope.driver,
          "ingress_binding_id" => @context.ingress_binding.public_id,
          "channel_connector_id" => @context.channel_connector.public_id,
          "channel_session_id" => @context.channel_session.public_id,
          "external_message_key" => @context.envelope.external_message_key,
          "external_sender_id" => @context.envelope.external_sender_id,
          "peer_kind" => @context.envelope.peer_kind,
          "peer_id" => @context.envelope.peer_id,
          "thread_key" => @context.envelope.thread_key,
        }
        @context
      end
    end
  end
end
