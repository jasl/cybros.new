module WorkspaceVariables
  class GetQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, key:)
      @workspace = workspace
      @key = key
    end

    def call
      relation.find_by(key: @key)
    end

    private

    def relation
      CanonicalVariable.where(
        workspace: @workspace,
        conversation: nil,
        scope: "workspace",
        current: true
      )
    end
  end
end
