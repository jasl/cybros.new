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
      workspace = existing_workspace
      return ensure_active_mount!(workspace) if workspace.present?

      created_workspace = nil

      Workspace.transaction(requires_new: true) do
        created_workspace = create_default_workspace!

        ensure_active_mount!(created_workspace)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      recovered_workspace = existing_workspace
      return ensure_active_mount!(recovered_workspace) if created_workspace.blank? && recovered_workspace.present?

      raise
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
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      active_mount_for(workspace).present? ? workspace.reload : raise
    end

    def active_mount_for(workspace)
      workspace.workspace_agents.where(agent: @agent, lifecycle_state: "active").order(:id).first
    end
  end
end
