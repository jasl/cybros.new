module AgentControl
  module ClosableResourceRouting
    module_function

    def execution_environment_for(resource)
      return resource.execution_environment if resource.respond_to?(:execution_environment)

      conversation_for(resource)&.execution_environment
    end

    def conversation_for(resource)
      return resource.conversation if resource.respond_to?(:conversation)

      turn = turn_for(resource)
      return turn.conversation if turn.present?

      resource.workflow_run&.conversation if resource.respond_to?(:workflow_run)
    end

    def turn_for(resource)
      return resource.turn if resource.respond_to?(:turn)

      resource.workflow_run&.turn if resource.respond_to?(:workflow_run)
    end

    def owning_agent_installation_for(resource)
      return resource.agent_installation if resource.respond_to?(:agent_installation)

      turn_for(resource)&.agent_deployment&.agent_installation
    end
  end
end
