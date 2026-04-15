module ClawBotSDK
  module Weixin
    class ContextTokenStore
      def self.fetch(channel_session:)
        channel_session.session_metadata.deep_stringify_keys["context_token"]
      end

      def self.store!(channel_session:, context_token:)
        session_metadata = channel_session.session_metadata.deep_stringify_keys
        channel_session.update!(
          session_metadata: session_metadata.merge("context_token" => context_token)
        )
      end
    end
  end
end
