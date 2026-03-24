module ConversationVariables
  class MgetQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, conversation:, keys:)
      @workspace = workspace
      @conversation = conversation
      @keys = Array(keys).map(&:to_s)
    end

    def call
      indexed_values = ConversationVariables::ListQuery.call(
        workspace: @workspace,
        conversation: @conversation
      ).index_by(&:key)

      @keys.index_with { |key| indexed_values[key] }
    end
  end
end
