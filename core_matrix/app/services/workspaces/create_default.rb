module Workspaces
  class CreateDefault
    DEFAULT_NAME = "Default Workspace".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(user_agent_binding: nil, user: nil, agent: nil, name: DEFAULT_NAME)
      @user = user || user_agent_binding&.user
      @agent = agent || user_agent_binding&.agent
      @name = name
    end

    def call
      existing_workspace || create_default_workspace!
    end

    def existing_workspace
      Workspace.find_by(
        installation: @user.installation,
        user: @user,
        agent: @agent,
        is_default: true
      )
    end

    private

    def create_default_workspace!
      Workspace.create!(
        installation: @user.installation,
        user: @user,
        agent: @agent,
        default_execution_runtime: @agent.default_execution_runtime,
        name: @name,
        privacy: "private",
        is_default: true
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      existing_workspace || raise
    end
  end
end
