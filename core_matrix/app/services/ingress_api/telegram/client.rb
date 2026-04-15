require "telegram/bot"

module IngressAPI
  module Telegram
    class Client
      FILE_API_BASE = "https://api.telegram.org/file".freeze

      def self.for_channel_connector(channel_connector, bot: nil)
        new(bot_token: bot_token_for(channel_connector), bot: bot)
      end

      def self.bot_token_for(channel_connector)
        token = channel_connector.credential_ref_payload["bot_token"].to_s
        raise ArgumentError, "telegram bot token is missing" if token.blank?

        token
      end

      def initialize(bot_token:, bot: nil)
        @bot_token = bot_token.to_s
        @bot = bot
      end

      def send_message(**kwargs)
        dispatch(:send_message, **kwargs)
      end

      def edit_message_text(**kwargs)
        dispatch(:edit_message_text, **kwargs)
      end

      def send_chat_action(**kwargs)
        dispatch(:send_chat_action, **kwargs)
      end

      def send_photo(**kwargs)
        dispatch(:send_photo, **kwargs)
      end

      def send_document(**kwargs)
        dispatch(:send_document, **kwargs)
      end

      def get_file(**kwargs)
        dispatch(:get_file, **kwargs)
      end

      def file_download_url(file_path)
        "#{FILE_API_BASE}/bot#{@bot_token}/#{file_path}"
      end

      private

      def dispatch(method_name, **kwargs)
        with_bot { |bot| bot.public_send(method_name, **kwargs) }
      end

      def with_bot
        return yield @bot if @bot.present?

        bot = ::Telegram::Bot::Client.new(@bot_token)
        yield bot
      end
    end
  end
end
