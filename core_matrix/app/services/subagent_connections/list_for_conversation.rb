module SubagentConnections
  class ListForConversation
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      @conversation.owned_subagent_connections
        .includes(:conversation, :origin_turn, :parent_subagent_connection)
        .order(:id)
        .map { |session| serialize(session) }
    end

    private

    def serialize(session)
      {
        "subagent_connection_id" => session.public_id,
        "conversation_id" => session.conversation.public_id,
        "origin_turn_id" => session.origin_turn&.public_id,
        "parent_subagent_connection_id" => session.parent_subagent_connection&.public_id,
        "profile_key" => session.profile_key,
        "scope" => session.scope,
        "derived_close_status" => session.derived_close_status,
        "observed_status" => session.observed_status,
        "subagent_depth" => session.depth,
      }.compact
    end
  end
end
