module SubagentSessions
  class OwnedTree
    def self.session_ids_for(owner_conversation:)
      new(owner_conversation: owner_conversation).session_ids
    end

    def self.conversation_ids_for(owner_conversation:)
      new(owner_conversation: owner_conversation).conversation_ids
    end

    def self.sessions_for(owner_conversation:)
      new(owner_conversation: owner_conversation).sessions
    end

    def initialize(owner_conversation:)
      @owner_conversation = owner_conversation
    end

    def sessions
      @sessions ||= begin
        collected = []
        frontier_owner_ids = [@owner_conversation.id]
        seen_session_ids = {}

        while frontier_owner_ids.any?
          batch = SubagentSession.where(owner_conversation_id: frontier_owner_ids).to_a
          frontier_owner_ids = []

          batch.each do |session|
            next if seen_session_ids[session.id]

            seen_session_ids[session.id] = true
            collected << session
            frontier_owner_ids << session.conversation_id
          end
        end

        collected
      end
    end

    def session_ids
      @session_ids ||= sessions.map(&:id)
    end

    def conversation_ids
      @conversation_ids ||= sessions.map(&:conversation_id)
    end
  end
end
