module CoreMatrixCLI
  module UseCases
    class CreateWorkspace < Base
      def call(name:, privacy:, is_default:)
        payload = authenticated_api.create_workspace(name: name, privacy: privacy, is_default: is_default)
        workspace = payload.fetch("workspace")

        persist_workspace_context(workspace_id: workspace.fetch("workspace_id"))
        payload
      end
    end
  end
end
