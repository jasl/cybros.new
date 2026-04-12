module AppSurface
  module Policies
    class WorkspaceAccess
      def self.call(...)
        new(...).call
      end

      def initialize(user:, workspace:)
        @user = user
        @workspace = workspace
      end

      def call
        ResourceVisibility::Usability.workspace_accessible_by_user?(
          user: @user,
          workspace: @workspace
        )
      end
    end
  end
end
