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
        .order(is_default: :desc, name: :asc, id: :asc)
        .to_a
    end
  end
end
