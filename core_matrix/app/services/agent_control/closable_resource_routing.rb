module AgentControl
  module ClosableResourceRouting
    module_function

    def execution_runtime_for(resource)
      return resource.execution_runtime if resource.respond_to?(:execution_runtime)

      turn_for(resource)&.execution_runtime
    end

    def conversation_for(resource)
      return resource.owner_conversation if resource.is_a?(SubagentConnection)
      return resource.conversation if resource.respond_to?(:conversation)

      turn = turn_for(resource)
      return turn.conversation if turn.present?

      resource.workflow_run&.conversation if resource.respond_to?(:workflow_run)
    end

    def turn_for(resource)
      return resource.origin_turn if resource.respond_to?(:origin_turn) && resource.origin_turn.present?
      return resource.turn if resource.respond_to?(:turn)

      resource.workflow_run&.turn if resource.respond_to?(:workflow_run)
    end

    def owning_agent_for(resource)
      return resource.agent if resource.respond_to?(:agent)

      turn_for(resource)&.agent_definition_version&.agent ||
        conversation_for(resource)&.agent
    end
  end
end
