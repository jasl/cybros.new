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
        sql = SubagentSession.send(
          :sanitize_sql_array,
          [
            <<~SQL.squish,
            WITH RECURSIVE owned_sessions AS (
              SELECT subagent_sessions.id,
                     subagent_sessions.conversation_id
              FROM subagent_sessions
              WHERE subagent_sessions.installation_id = :installation_id
                AND subagent_sessions.owner_conversation_id = :owner_conversation_id
              UNION
              SELECT child_sessions.id,
                     child_sessions.conversation_id
              FROM subagent_sessions child_sessions
              INNER JOIN owned_sessions
                ON child_sessions.owner_conversation_id = owned_sessions.conversation_id
              WHERE child_sessions.installation_id = :installation_id
            )
            SELECT subagent_sessions.*
            FROM subagent_sessions
            INNER JOIN owned_sessions
              ON owned_sessions.id = subagent_sessions.id
            ORDER BY subagent_sessions.created_at ASC, subagent_sessions.id ASC
            SQL
            {
              installation_id: @owner_conversation.installation_id,
              owner_conversation_id: @owner_conversation.id,
            },
          ]
        )

        SubagentSession.find_by_sql(sql)
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
