module Workspaces
  class MaterializeDefault
    DEFAULT_NAME = CreateDefault::DEFAULT_NAME

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent:, name: DEFAULT_NAME)
      @user = user
      @agent = agent
      @name = name
    end

    def call
      existing_workspace || Workspaces::CreateDefault.call(user: @user, agent: @agent, name: @name)
    end

    private

    def existing_workspace
      Workspace.find_by(
        installation_id: @user.installation_id,
        user: @user,
        agent: @agent,
        is_default: true
      )
    end
  end
end
