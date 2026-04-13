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
      existing_workspace || create_default_workspace!
    end

    def existing_workspace
      Workspace.find_by(
        installation_id: @user.installation_id,
        user: @user,
        agent: @agent,
        is_default: true
      )
    end

    private

    def create_default_workspace!
      Workspace.create!(
        installation_id: @user.installation_id,
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
