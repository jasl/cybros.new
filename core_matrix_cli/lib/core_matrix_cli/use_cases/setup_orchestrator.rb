module CoreMatrixCLI
  module UseCases
    class SetupOrchestrator < Base
      def persist_auth_payload(payload)
        super
        persist_workspace_context(
          workspace_id: payload.dig("workspace", "workspace_id"),
          workspace_agent_id: payload.dig("workspace_agent", "workspace_agent_id")
        )
      end

      def prime_workspace_context!
        workspaces = authenticated_api.list_workspaces.fetch("workspaces", [])
        workspace = select_workspace(workspaces)
        workspace_agent = select_workspace_agent(workspace)

        persist_workspace_context(
          workspace_id: workspace&.dig("workspace_id"),
          workspace_agent_id: workspace_agent&.dig("workspace_agent_id")
        )

        {
          "workspace" => workspace,
          "workspace_agent" => workspace_agent,
        }.compact
      end

      def readiness_snapshot
        ShowStatus.new(
          config_repository: config_repository,
          credential_repository: credential_repository,
          api_factory: api_factory,
          browser_launcher: browser_launcher,
          qr_renderer: qr_renderer,
          polling: polling,
          time_source: time_source
        ).call
      end
    end
  end
end
