module ChannelSessions
  class RebindFromConversationContext
    def self.call(...)
      new(...).call
    end

    def initialize(channel_session:, source_conversation:)
      @channel_session = channel_session
      @source_conversation = source_conversation
    end

    def call
      ApplicationRecord.transaction do
        managed_conversation = Conversations::CreateManagedChannelConversation.call(
          source_conversation: @source_conversation,
          platform: @channel_session.platform,
          peer_kind: @channel_session.peer_kind,
          peer_id: @channel_session.peer_id,
          session_metadata: @channel_session.session_metadata
        )
        @channel_session.update!(conversation: managed_conversation)
        managed_conversation
      end
    end
  end
end
