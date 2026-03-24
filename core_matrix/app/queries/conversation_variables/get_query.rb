module ConversationVariables
  class GetQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, conversation:, key:)
      @workspace = workspace
      @conversation = conversation
      @key = key
    end

    def call
      relation.find_by(key: @key)
    end

    private

    def relation
      CanonicalVariable.where(
        workspace: @workspace,
        conversation: @conversation,
        scope: "conversation",
        current: true
      )
    end
  end
end
