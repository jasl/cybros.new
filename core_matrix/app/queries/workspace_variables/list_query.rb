module WorkspaceVariables
  class ListQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:)
      @workspace = workspace
    end

    def call
      CanonicalVariable.where(
        workspace: @workspace,
        conversation: nil,
        scope: "workspace",
        current: true
      ).order(:key, :created_at).to_a
    end
  end
end
