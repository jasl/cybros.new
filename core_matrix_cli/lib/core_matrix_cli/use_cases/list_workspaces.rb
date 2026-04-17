module CoreMatrixCLI
  module UseCases
    class ListWorkspaces < Base
      def call
        authenticated_api.list_workspaces
      end
    end
  end
end
