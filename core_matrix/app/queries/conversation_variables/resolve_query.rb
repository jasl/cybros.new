module ConversationVariables
  class ResolveQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, conversation:)
      @workspace = workspace
      @conversation = conversation
    end

    def call
      WorkspaceVariables::ListQuery.call(workspace: @workspace)
        .index_by(&:key)
        .merge(conversation_visible_values.index_by(&:key))
    end

    private

    def conversation_visible_values
      keys = []
      cursor = nil

      loop do
        page = LineageStores::ListKeysQuery.call(
          reference_owner: @conversation,
          cursor: cursor,
          limit: 100
        )
        keys.concat(page.items.map(&:key))
        break if page.next_cursor.blank?

        cursor = page.next_cursor
      end

      LineageStores::MultiGetQuery.call(
        reference_owner: @conversation,
        keys: keys
      ).values.compact
    end
  end
end
