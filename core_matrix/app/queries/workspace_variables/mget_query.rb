module WorkspaceVariables
  class MgetQuery
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, keys:)
      @workspace = workspace
      @keys = Array(keys).map(&:to_s)
    end

    def call
      indexed_values = WorkspaceVariables::ListQuery.call(workspace: @workspace).index_by(&:key)
      @keys.index_with { |key| indexed_values[key] }
    end
  end
end
