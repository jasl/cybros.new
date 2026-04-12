module AppSurface
  module Presenters
    class WorkspacePresenter
      def self.call(...)
        new(...).call
      end

      def initialize(workspace:)
        @workspace = workspace
      end

      def call
        {
          "workspace_id" => @workspace.public_id,
          "agent_id" => @workspace.user_agent_binding.agent.public_id,
          "default_execution_runtime_id" => @workspace.default_execution_runtime&.public_id,
          "name" => @workspace.name,
          "privacy" => @workspace.privacy,
          "is_default" => @workspace.is_default,
          "created_at" => @workspace.created_at&.iso8601(6),
          "updated_at" => @workspace.updated_at&.iso8601(6),
        }.compact
      end
    end
  end
end
