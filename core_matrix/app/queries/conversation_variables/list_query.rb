module ConversationVariables
  class ListQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, conversation:)
      @workspace = workspace
      @conversation = conversation
    end

    def call
      CanonicalVariable.where(
        workspace: @workspace,
        conversation: @conversation,
        scope: "conversation",
        current: true
      ).order(:key, :created_at).to_a
    end
  end
end
