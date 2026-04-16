module Conversations
  module Metadata
    class BuildManagedChannelTitle
      def self.call(...)
        new(...).call
      end

      def initialize(platform:, peer_kind:, peer_id:, session_metadata: {})
        @platform = platform.to_s
        @peer_kind = peer_kind.to_s
        @peer_id = peer_id.to_s
        @session_metadata = session_metadata.is_a?(Hash) ? session_metadata.deep_stringify_keys : {}
      end

      def call
        return if @platform.blank? || @peer_kind.blank? || @peer_id.blank?

        [platform_label, peer_kind_label, peer_identity].join(" ")
      end

      private

      def platform_label
        case @platform
        when "telegram"
          "Telegram"
        when "telegram_webhook"
          "Telegram Webhook"
        else
          @platform.tr("_", " ").titleize
        end
      end

      def peer_kind_label
        case @peer_kind
        when "dm"
          "DM"
        else
          @peer_kind.titleize
        end
      end

      def peer_identity
        username = @session_metadata["sender_username"].to_s
        return "@#{username.delete_prefix("@")}" if username.present?

        @peer_id
      end
    end
  end
end
