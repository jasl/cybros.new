module AppSurface
  module Policies
    class AdminAccess
      def self.call(...)
        new(...).call
      end

      def initialize(user:, installation: nil)
        @user = user
        @installation = installation
      end

      def call
        return false if @user.blank?
        return false unless @user.admin?
        return true if @installation.blank?

        @user.installation_id == @installation.id
      end
    end
  end
end
