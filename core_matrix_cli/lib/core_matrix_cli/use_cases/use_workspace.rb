module CoreMatrixCLI
  module UseCases
    class UseWorkspace < Base
      def call(workspace_id:)
        persist_workspace_context(workspace_id: workspace_id)
        workspace_id
      end
    end
  end
end
