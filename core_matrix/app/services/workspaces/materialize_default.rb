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
      Workspaces::CreateDefault.call(user: @user, agent: @agent, name: @name)
    end
  end
end
