module SubagentConnections
  class OwnedTree
    def self.connection_ids_for(owner_conversation:)
      new(owner_conversation: owner_conversation).connection_ids
    end

    def self.conversation_ids_for(owner_conversation:)
      new(owner_conversation: owner_conversation).conversation_ids
    end

    def self.connections_for(owner_conversation:)
      new(owner_conversation: owner_conversation).connections
    end

    def initialize(owner_conversation:)
      @owner_conversation = owner_conversation
    end

    def connections
      @connections ||= begin
        sql = SubagentConnection.send(
          :sanitize_sql_array,
          [
            <<~SQL.squish,
            WITH RECURSIVE owned_connections AS (
              SELECT subagent_connections.id,
                     subagent_connections.conversation_id
              FROM subagent_connections
              WHERE subagent_connections.installation_id = :installation_id
                AND subagent_connections.owner_conversation_id = :owner_conversation_id
              UNION
              SELECT child_connections.id,
                     child_connections.conversation_id
              FROM subagent_connections child_connections
              INNER JOIN owned_connections
                ON child_connections.owner_conversation_id = owned_connections.conversation_id
              WHERE child_connections.installation_id = :installation_id
            )
            SELECT subagent_connections.*
            FROM subagent_connections
            INNER JOIN owned_connections
              ON owned_connections.id = subagent_connections.id
            ORDER BY subagent_connections.created_at ASC, subagent_connections.id ASC
            SQL
            {
              installation_id: @owner_conversation.installation_id,
              owner_conversation_id: @owner_conversation.id,
            },
          ]
        )

        SubagentConnection.find_by_sql(sql)
      end
    end

    def connection_ids
      @connection_ids ||= connections.map(&:id)
    end

    def conversation_ids
      @conversation_ids ||= connections.map(&:conversation_id)
    end
  end
end
