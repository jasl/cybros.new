module SubagentSessions
  class ListForConversation
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      @conversation.owned_subagent_sessions
        .includes(:conversation, :origin_turn, :parent_subagent_session)
        .order(:id)
        .map { |session| serialize(session) }
    end

    private

    def serialize(session)
      {
        "subagent_session_id" => session.public_id,
        "conversation_id" => session.conversation.public_id,
        "origin_turn_id" => session.origin_turn&.public_id,
        "parent_subagent_session_id" => session.parent_subagent_session&.public_id,
        "profile_key" => session.profile_key,
        "scope" => session.scope,
        "lifecycle_state" => session.lifecycle_state,
        "last_known_status" => session.last_known_status,
        "canonical_name" => session.canonical_name,
        "nickname" => session.nickname,
        "subagent_depth" => session.depth,
      }.compact
    end
  end
end
