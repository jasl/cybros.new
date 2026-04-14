module Workspaces
  class ForUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      Workspace
        .accessible_to_user(@user)
        .includes(workspace_agents: :default_execution_runtime)
        .order(is_default: :desc, name: :asc, id: :asc)
        .to_a
    end
  end
end
