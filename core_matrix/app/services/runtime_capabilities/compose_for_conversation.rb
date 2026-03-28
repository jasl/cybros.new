module RuntimeCapabilities
  class ComposeForConversation
    def self.call(...)
      new(...).call
    end

    def initialize(execution_environment:, agent_deployment:)
      @execution_environment = execution_environment
      @agent_deployment = agent_deployment
    end

    def call
      RuntimeCapabilityContract.build(
        execution_environment: @execution_environment,
        capability_snapshot: @agent_deployment.active_capability_snapshot
      ).conversation_payload(
        execution_environment_id: @execution_environment.public_id,
        agent_deployment_id: @agent_deployment.public_id
      )
    end
  end
end
