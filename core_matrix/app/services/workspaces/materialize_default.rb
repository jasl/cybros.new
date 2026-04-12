module Workspaces
  class MaterializeDefault
    DEFAULT_NAME = CreateDefault::DEFAULT_NAME

    def self.call(...)
      new(...).call
    end

    def initialize(user_agent_binding:, name: DEFAULT_NAME)
      @user_agent_binding = user_agent_binding
      @name = name
    end

    def call
      existing_workspace || Workspaces::CreateDefault.call(
        user_agent_binding: @user_agent_binding,
        name: @name
      )
    end

    private

    def existing_workspace
      Workspace.find_by(user_agent_binding: @user_agent_binding, is_default: true)
    end
  end
end
