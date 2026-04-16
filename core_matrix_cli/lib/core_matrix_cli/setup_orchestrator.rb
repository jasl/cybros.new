module CoreMatrixCLI
  class SetupOrchestrator
    def initialize(runtime:)
      @runtime = runtime
    end

    def persist_auth_payload(payload)
      session_token = payload["session_token"]
      @runtime.persist_session_token(session_token) if session_token
      @runtime.persist_operator_email(payload.dig("user", "email")) if payload.dig("user", "email")

      @runtime.persist_workspace_context(
        workspace_id: payload.dig("workspace", "workspace_id"),
        workspace_agent_id: payload.dig("workspace_agent", "workspace_agent_id")
      )
    end

    def prime_workspace_context!
      workspaces = @runtime.list_workspaces.fetch("workspaces", [])
      workspace = select_workspace(workspaces)
      workspace_agent = select_workspace_agent(workspace)

      @runtime.persist_workspace_context(
        workspace_id: workspace&.dig("workspace_id"),
        workspace_agent_id: workspace_agent&.dig("workspace_agent_id")
      )

      {
        "workspace" => workspace,
        "workspace_agent" => workspace_agent,
      }.compact
    end

    def readiness_snapshot
      @runtime.readiness_snapshot
    end

    private

    def select_workspace(workspaces)
      workspaces.find { |workspace| workspace["is_default"] } || workspaces.first
    end

    def select_workspace_agent(workspace)
      return nil if workspace.nil?

      Array(workspace["workspace_agents"]).first
    end
  end
end
