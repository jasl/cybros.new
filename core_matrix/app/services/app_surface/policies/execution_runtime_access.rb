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
        ResourceVisibility::Usability.execution_runtime_usable_by_user?(
          user: @user,
          execution_runtime: @execution_runtime
        )
      end
    end
  end
end
