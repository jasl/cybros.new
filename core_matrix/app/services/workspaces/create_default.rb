module Workspaces
  class CreateDefault
    DEFAULT_NAME = "Default Workspace".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(user_agent_binding:, name: DEFAULT_NAME)
      @user_agent_binding = user_agent_binding
      @name = name
    end

    def call
      existing_workspace || Workspace.create!(
        installation: @user_agent_binding.installation,
        user: @user_agent_binding.user,
        user_agent_binding: @user_agent_binding,
        name: @name,
        privacy: "private",
        is_default: true
      )
    end

    def existing_workspace
      Workspace.find_by(user_agent_binding: @user_agent_binding, is_default: true)
    end
  end
end
