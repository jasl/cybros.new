module Installations
  class BootstrapBundledAgentBinding
    Result = Struct.new(
      :agent_program,
      :executor_program,
      :deployment,
      :capability_snapshot,
      :agent_session,
      :executor_session,
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

      binding_result = UserProgramBindings::Enable.call(
        user: @user,
        agent_program: registry.agent_program
      )

      Result.new(
        agent_program: registry.agent_program,
        executor_program: registry.executor_program,
        deployment: registry.deployment,
        capability_snapshot: registry.capability_snapshot,
        agent_session: registry.agent_session,
        executor_session: registry.executor_session,
        binding: binding_result.binding,
        workspace: binding_result.workspace
      )
    end
  end
end
