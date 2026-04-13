module AppSurface
  module Policies
    class ExecutionRuntimeAccess
      def self.call(...)
        new(...).call
      end

      def initialize(user:, execution_runtime:)
        @user = user
        @execution_runtime = execution_runtime
      end

      def call
        return false if @user.blank? || @execution_runtime.blank?

        ExecutionRuntime.visible_to_user(@user).where(id: @execution_runtime.id).exists?
      end
    end
  end
end
