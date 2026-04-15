module Installations
  class BootstrapBundledAgentBinding
    Result = Struct.new(
      :agent,
      :execution_runtime,
      :agent_definition_version,
      :agent_connection,
      :execution_runtime_connection,
      :workspace,
      :workspace_agent,
      :default_workspace_ref,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, user:, configuration: Rails.configuration.x.bundled_agent)
      @installation = installation
      @user = user
      @configuration = configuration
    end

    def call
      registry = Installations::RegisterBundledAgentRuntime.call(
        installation: @installation,
        configuration: @configuration
      )
      return unless registry.present?

      workspace = Workspaces::CreateDefault.call(
        user: @user,
        agent: registry.agent
      )
      workspace_agent = workspace.workspace_agents.where(agent: registry.agent, lifecycle_state: "active").order(:id).first
      default_workspace_ref = Workspaces::ResolveDefaultReference.call(
        user: @user,
        agent: registry.agent,
        workspace: workspace
      )

      Result.new(
        agent: registry.agent,
        execution_runtime: registry.execution_runtime,
        agent_definition_version: registry.agent_definition_version,
        agent_connection: registry.agent_connection,
        execution_runtime_connection: registry.execution_runtime_connection,
        workspace: workspace,
        workspace_agent: workspace_agent,
        default_workspace_ref: default_workspace_ref
      )
    end
  end
end
