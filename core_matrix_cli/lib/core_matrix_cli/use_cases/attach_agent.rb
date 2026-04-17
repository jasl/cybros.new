module CoreMatrixCLI
  module UseCases
    class AttachAgent < Base
      def call(workspace_id:, agent_id:)
        payload = authenticated_api.attach_workspace_agent(workspace_id: workspace_id, agent_id: agent_id)
        workspace_agent = payload.fetch("workspace_agent")

        persist_workspace_context(
          workspace_id: workspace_agent.fetch("workspace_id"),
          workspace_agent_id: workspace_agent.fetch("workspace_agent_id")
        )
        payload
      end
    end
  end
end
