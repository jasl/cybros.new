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
        return false if @user.blank? || @workspace.blank?

        Workspace.accessible_to_user(@user).where(id: @workspace.id).exists?
      end
    end
  end
end
