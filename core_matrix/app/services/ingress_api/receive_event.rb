module IngressAPI
  class ReceiveEvent
    MIDDLEWARE = [
      IngressAPI::Middleware::CaptureRawPayload,
      IngressAPI::Middleware::VerifyRequest,
      IngressAPI::Middleware::DeduplicateInbound,
    ].freeze
    PREPROCESSORS = [
      IngressAPI::Preprocessors::ResolveChannelSession,
      IngressAPI::Preprocessors::AuthorizeAndPair,
      IngressAPI::Preprocessors::CreateOrBindConversation,
      IngressAPI::Preprocessors::DispatchCommand,
      IngressAPI::Preprocessors::CoalesceBurst,
      IngressAPI::Preprocessors::MaterializeAttachments,
      IngressAPI::Preprocessors::ResolveDispatchDecision,
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(adapter:, raw_payload:, request_metadata: {}, middleware: MIDDLEWARE, preprocessors: PREPROCESSORS)
      @adapter = adapter
      @raw_payload = raw_payload
      @request_metadata = request_metadata
      @middleware = middleware
      @preprocessors = preprocessors
    end

    def call
      context = IngressAPI::Context.new(request_metadata: @request_metadata.deep_stringify_keys, pipeline_trace: [])

      @middleware.first.call(context:, raw_payload: @raw_payload)
      @middleware.second.call(context:, adapter: @adapter, raw_payload: @raw_payload, request_metadata: context.request_metadata)
      normalize_envelope!(context)
      @middleware.third.call(context:)
      return context.result if context.result.present?

      @preprocessors.each do |preprocessor|
        preprocessor.call(context:)
        return context.result if context.result.present?
      end

      IngressAPI::Result.ready_for_turn_entry(
        trace: context.pipeline_trace,
        envelope: context.envelope,
        conversation: context.conversation,
        channel_session: context.channel_session,
        request_metadata: context.request_metadata
      )
    end

    private

    def normalize_envelope!(context)
      context.append_trace("adapter_normalize_envelope")
      context.envelope = @adapter.normalize_envelope(
        raw_payload: @raw_payload,
        ingress_binding: context.ingress_binding,
        channel_connector: context.channel_connector,
        request_metadata: context.request_metadata
      )
    end
  end
end
