module ClawBotSDK
  module Weixin
    class MediaClient
      def initialize(client:)
        @client = client
      end

      def send_attachment(attachment:, to_user_id:, context_token:, text: nil)
        @client.send_text(
          to_user_id: to_user_id,
          text: [text, attachment["filename"]].compact.join("\n"),
          context_token: context_token
        )
      end
    end
  end
end
