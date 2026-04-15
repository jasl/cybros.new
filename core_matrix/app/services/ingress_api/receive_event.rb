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

    def initialize(adapter:, raw_payload:, request_metadata: {}, middleware: MIDDLEWARE, preprocessors: PREPROCESSORS, outbound_dispatcher: ChannelDeliveries::DispatchConversationOutput)
      @adapter = adapter
      @raw_payload = raw_payload
      @request_metadata = request_metadata
      @middleware = middleware
      @preprocessors = preprocessors
      @outbound_dispatcher = outbound_dispatcher
    end

    def call
      context = IngressAPI::Context.new(
        request_metadata: @request_metadata.deep_stringify_keys,
        raw_payload: @raw_payload,
        pipeline_trace: []
      )

      @middleware.first.call(context:, raw_payload: @raw_payload)
      @middleware.second.call(context:, adapter: @adapter, raw_payload: @raw_payload, request_metadata: context.request_metadata)
      normalize_envelope!(context)
      @middleware.third.call(context:)
      return context.result if context.result.present?

      @preprocessors.each do |preprocessor|
        preprocessor.call(context:)
        persist_channel_inbound_message!(context) if preprocessor == IngressAPI::Preprocessors::CreateOrBindConversation && context.result.blank?
        dispatch_handled_result!(context) if context.result&.handled?
        return context.result if context.result.present?
      end

      materialize_dispatch!(context)
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

    def persist_channel_inbound_message!(context)
      return context.channel_inbound_message if context.channel_inbound_message.present?
      return if context.channel_session.blank?

      context.channel_inbound_message = ChannelInboundMessage.create!(
        installation: context.ingress_binding.installation,
        ingress_binding: context.ingress_binding,
        channel_connector: context.channel_connector,
        channel_session: context.channel_session,
        conversation: context.conversation,
        external_event_key: context.envelope.external_event_key,
        external_message_key: context.envelope.external_message_key,
        external_sender_id: context.envelope.external_sender_id,
        sender_snapshot: context.envelope.sender_snapshot,
        content: {
          "text" => context.envelope.text,
          "attachments" => context.envelope.attachments,
        },
        normalized_payload: {
          "ingress_binding_id" => context.ingress_binding.public_id,
          "channel_connector_id" => context.channel_connector.public_id,
          "channel_session_id" => context.channel_session.public_id,
          "conversation_id" => context.conversation&.public_id,
          "reply_to_external_message_key" => context.envelope.reply_to_external_message_key,
          "quoted_external_message_key" => context.envelope.quoted_external_message_key,
          "quoted_text" => context.envelope.quoted_text,
          "quoted_sender_label" => context.envelope.quoted_sender_label,
          "quoted_attachment_refs" => Array(context.envelope.quoted_attachment_refs).map do |attachment|
            attachment.respond_to?(:deep_stringify_keys) ? attachment.deep_stringify_keys : attachment
          end,
        }.compact,
        raw_payload: context.envelope.raw_payload,
        received_at: context.envelope.occurred_at
      )
      context.coalesced_message_ids = [context.channel_inbound_message.public_id]
      context.channel_inbound_message
    end

    def dispatch_handled_result!(context)
      return unless context.result.handled?
      return unless context.result.handled_via == "sidecar_query"
      return if context.channel_session.blank? || context.conversation.blank?

      @outbound_dispatcher.call(
        conversation: context.conversation,
        channel_session: context.channel_session,
        text: context.result.payload.dig("human_sidechat", "content"),
        delivery_mode: context.result.payload["delivery_mode"],
        reply_to_external_message_key: context.channel_inbound_message&.external_message_key || context.envelope.external_message_key
      )
    end

    def materialize_dispatch!(context)
      context.append_trace("materialize_turn_entry")

      channel_inbound_message = persist_channel_inbound_message!(context)
      result =
        case context.dispatch_decision
        when "new_turn"
          IngressAPI::MaterializeTurnEntry.call(
            conversation: context.conversation,
            channel_inbound_message: channel_inbound_message,
            content: context.envelope.text,
            origin_payload: context.origin_payload,
            selector_source: "conversation",
            selector: nil,
            attachment_records: context.attachment_records
          )
        when "steer_current_turn"
          turn = Turns::SteerCurrentInput.call(
            turn: context.active_turn,
            content: context.envelope.text,
            origin_payload: context.origin_payload,
            source_ref_type: "ChannelInboundMessage",
            source_ref_id: channel_inbound_message.public_id
          )
          IngressAPI::AttachMaterializedAttachments.call(
            message: turn.selected_input_message,
            attachment_records: context.attachment_records
          )
          IngressAPI::MaterializeTurnEntry::Result.new(
            conversation: context.conversation,
            turn: turn,
            message: turn.selected_input_message
          )
        when "queue_follow_up"
          reference_turn = context.active_turn || latest_in_flight_turn(context.conversation)
          turn = Turns::QueueChannelFollowUp.call(
            conversation: context.conversation,
            content: context.envelope.text,
            origin_payload: context.origin_payload,
            source_ref_id: channel_inbound_message.public_id,
            resolved_config_snapshot: reference_turn.resolved_config_snapshot,
            resolved_model_selection_snapshot: reference_turn.resolved_model_selection_snapshot
          )
          IngressAPI::AttachMaterializedAttachments.call(
            message: turn.selected_input_message,
            attachment_records: context.attachment_records
          )
          IngressAPI::MaterializeTurnEntry::Result.new(
            conversation: context.conversation,
            turn: turn,
            message: turn.selected_input_message
          )
        else
          return IngressAPI::Result.rejected(
            rejection_reason: "unsupported_dispatch_decision",
            trace: context.pipeline_trace,
            envelope: context.envelope,
            conversation: context.conversation,
            channel_session: context.channel_session,
            request_metadata: context.request_metadata
          )
        end

      IngressAPI::Result.handled(
        handled_via: "transcript_entry",
        trace: context.pipeline_trace,
        envelope: context.envelope,
        conversation: result.conversation,
        channel_session: context.channel_session,
        request_metadata: context.request_metadata
      )
    end

    def latest_in_flight_turn(conversation)
      conversation.turns.where(lifecycle_state: %w[queued active]).order(sequence: :desc).first
    end
  end
end
