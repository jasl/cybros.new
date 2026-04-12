module Installations
  class BootstrapBundledAgentBinding
    Result = Struct.new(
      :agent,
      :execution_runtime,
      :agent_definition_version,
      :agent_connection,
      :execution_runtime_connection,
      :binding,
      :workspace,
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

      binding_result = UserAgentBindings::Enable.call(
        user: @user,
        agent: registry.agent
      )

      Result.new(
        agent: registry.agent,
        execution_runtime: registry.execution_runtime,
        agent_definition_version: registry.agent_definition_version,
        agent_connection: registry.agent_connection,
        execution_runtime_connection: registry.execution_runtime_connection,
        binding: binding_result.binding,
        workspace: binding_result.workspace
      )
    end
  end
end
