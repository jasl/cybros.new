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
        .merge(
          ConversationVariables::ListQuery.call(
            workspace: @workspace,
            conversation: @conversation
          ).index_by(&:key)
        )
    end
  end
end
