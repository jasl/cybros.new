module AppSurface
  module Actions
    module Workspaces
      class Create
        def self.call(...)
          new(...).call
        end

        def initialize(user:, name:, privacy: nil, is_default: false)
          @user = user
          @name = name
          @privacy = privacy
          @is_default = ActiveModel::Type::Boolean.new.cast(is_default) || false
        end

        def call
          Workspace.create!(
            installation: @user.installation,
            user: @user,
            name: @name,
            privacy: @privacy.presence || "private",
            is_default: @is_default
          )
        end
      end
    end
  end
end
