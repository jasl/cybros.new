module Installations
  class BootstrapBundledAgentBinding
    Result = Struct.new(:agent_installation, :execution_environment, :deployment, :capability_snapshot, :binding, :workspace, keyword_init: true)

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
        agent_installation: registry.agent_installation
      )

      Result.new(
        agent_installation: registry.agent_installation,
        execution_environment: registry.execution_environment,
        deployment: registry.deployment,
        capability_snapshot: registry.capability_snapshot,
        binding: binding_result.binding,
        workspace: binding_result.workspace
      )
    end
  end
end
