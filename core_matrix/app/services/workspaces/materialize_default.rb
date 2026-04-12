module Workspaces
  class MaterializeDefault
    DEFAULT_NAME = CreateDefault::DEFAULT_NAME

    def self.call(...)
      new(...).call
    end

    def initialize(user_agent_binding: nil, user: nil, agent: nil, name: DEFAULT_NAME)
      @user = user || user_agent_binding&.user
      @agent = agent || user_agent_binding&.agent
      @name = name
    end

    def call
      existing_workspace || Workspaces::CreateDefault.call(user: @user, agent: @agent, name: @name)
    end

    private

    def existing_workspace
      Workspace.find_by(
        installation: @user.installation,
        user: @user,
        agent: @agent,
        is_default: true
      )
    end
  end
end
