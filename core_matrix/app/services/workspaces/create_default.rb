module Workspaces
  class CreateDefault
    DEFAULT_NAME = "Default Workspace".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent:, name: DEFAULT_NAME)
      @user = user
      @agent = agent
      @name = name
    end

    def call
      workspace = existing_workspace || create_default_workspace!

      ensure_active_mount!(workspace)
    end

    def existing_workspace
      Workspace.find_by(
        installation_id: @user.installation_id,
        user: @user,
        is_default: true
      )
    end

    private

    def create_default_workspace!
      Workspace.create!(
        installation_id: @user.installation_id,
        user: @user,
        name: @name,
        privacy: "private",
        is_default: true
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      existing_workspace || raise
    end

    def ensure_active_mount!(workspace)
      return workspace if active_mount_for(workspace).present?

      WorkspaceAgent.create!(
        installation_id: @user.installation_id,
        workspace: workspace,
        agent: @agent,
        default_execution_runtime: @agent.default_execution_runtime,
        entry_policy_payload: Conversation.default_interactive_entry_policy_payload
      )

      workspace.reload
    end

    def active_mount_for(workspace)
      workspace.workspace_agents.where(agent: @agent, lifecycle_state: "active").order(:id).first
    end
  end
end
