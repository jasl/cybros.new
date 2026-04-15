module ChannelDeliveries
  class DispatchConversationOutput
    PREVIEW_MESSAGE_ID_KEY = "telegram_preview_message_id".freeze
    PREVIEW_EXTERNAL_MESSAGE_KEY = "telegram_preview_external_message_key".freeze
    PREVIEW_BUFFER_KEY = "telegram_preview_buffer".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turn: nil, message: nil, channel_session: nil, text: nil, delivery_mode: nil, attachments: nil, chat_action: nil, reply_to_external_message_key: nil, delivery_sender: nil)
      @conversation = conversation
      @turn = turn
      @message = message
      @channel_session = channel_session
      @text = text
      @delivery_mode = delivery_mode
      @attachments = attachments
      @chat_action = chat_action
      @reply_to_external_message_key = reply_to_external_message_key
      @delivery_sender = delivery_sender
    end

    def call
      target_sessions.filter_map do |channel_session|
        delivery = create_delivery!(channel_session)
        dispatch_delivery!(delivery)
        update_session_delivery_state!(channel_session, delivery)
        delivery
      rescue StandardError
        nil
      end
    end

    private

    def target_sessions
      return [@channel_session] if @channel_session.present?

      ChannelSession.where(
        installation_id: @conversation.installation_id,
        conversation_id: @conversation.id,
        binding_state: "active"
      ).order(:id).to_a
    end

    def create_delivery!(channel_session)
      ChannelDelivery.create!(
        installation: channel_session.installation,
        ingress_binding: channel_session.ingress_binding,
        channel_connector: channel_session.channel_connector,
        channel_session: channel_session,
        conversation: @conversation,
        turn: @turn,
        message: @message,
        external_message_key: fallback_external_message_key(channel_session),
        reply_to_external_message_key: resolved_reply_to_external_message_key,
        payload: build_payload(channel_session),
        failure_payload: {}
      )
    end

    def dispatch_delivery!(delivery)
      if @delivery_sender.respond_to?(:call)
        @delivery_sender.call(channel_delivery: delivery)
        return
      end

      case delivery.channel_connector.platform
      when "telegram"
        ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery)
      else
        raise ArgumentError, "unsupported channel delivery platform: #{delivery.channel_connector.platform}"
      end
    end

    def update_session_delivery_state!(channel_session, delivery)
      session_metadata = channel_session.session_metadata.deep_stringify_keys
      payload = delivery.payload.deep_stringify_keys

      if payload["delivery_mode"] == "preview_stream"
        if @message.present? && payload["preview_message_id"].present?
          session_metadata.delete(PREVIEW_MESSAGE_ID_KEY)
          session_metadata.delete(PREVIEW_EXTERNAL_MESSAGE_KEY)
          session_metadata.delete(PREVIEW_BUFFER_KEY)
        elsif delivery.external_message_key.present?
          preview_message_id = parse_telegram_message_id(delivery.external_message_key)
          session_metadata[PREVIEW_MESSAGE_ID_KEY] = preview_message_id if preview_message_id.present?
          session_metadata[PREVIEW_EXTERNAL_MESSAGE_KEY] = delivery.external_message_key
        end
      end

      channel_session.update!(
        last_outbound_at: Time.current,
        session_metadata: session_metadata
      )
    end

    def build_payload(channel_session)
      payload = {
        "text" => resolved_text,
        "delivery_mode" => resolved_delivery_mode(channel_session),
        "attachments" => resolved_attachments,
      }.compact

      payload["chat_action"] = @chat_action if @chat_action.present?

      preview_message_id = preview_message_id_for(channel_session)
      payload["preview_message_id"] = preview_message_id if preview_message_id.present?
      payload
    end

    def resolved_text
      @text.to_s.presence || @message&.content.to_s.presence
    end

    def resolved_delivery_mode(channel_session)
      return @delivery_mode if @delivery_mode.present?
      return "preview_stream" if @message.present? && preview_message_id_for(channel_session).present?

      "final_delivery"
    end

    def resolved_attachments
      return Array(@attachments).presence if @attachments.present?
      return [] if @message.blank?

      @message.message_attachments.order(:id).map do |attachment|
        blob = attachment.file.blob
        {
          "attachment_id" => attachment.public_id,
          "filename" => blob.filename.to_s,
          "content_type" => blob.content_type,
          "byte_size" => blob.byte_size,
          "modality" => modality_for(blob.content_type)
        }
      end
    end

    def modality_for(content_type)
      return "image" if content_type.to_s.start_with?("image/")

      "file"
    end

    def preview_message_id_for(channel_session)
      session_metadata = channel_session.session_metadata.deep_stringify_keys
      session_metadata[PREVIEW_MESSAGE_ID_KEY]
    end

    def resolved_reply_to_external_message_key
      @reply_to_external_message_key.presence ||
        @turn&.origin_payload&.dig("external_message_key")
    end

    def fallback_external_message_key(channel_session)
      channel_session.session_metadata.deep_stringify_keys[PREVIEW_EXTERNAL_MESSAGE_KEY] ||
        resolved_reply_to_external_message_key ||
        "pending:#{SecureRandom.uuid}"
    end

    def parse_telegram_message_id(external_message_key)
      match = external_message_key.to_s.match(/\Atelegram:chat:[^:]+:message:(\d+)\z/)
      match && match[1].to_i
    end
  end
end
