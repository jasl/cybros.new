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
        .where(installation: @user.installation, user: @user, privacy: "private")
        .includes(:default_execution_runtime, user_agent_binding: { agent: :default_execution_runtime })
        .order(is_default: :desc, name: :asc, id: :asc)
        .to_a
        .select { |workspace| ResourceVisibility::Usability.workspace_accessible_by_user?(user: @user, workspace: workspace) }
    end
  end
end
