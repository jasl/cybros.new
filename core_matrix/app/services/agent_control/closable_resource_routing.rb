module AgentControl
  module ClosableResourceRouting
    module_function

    def executor_program_for(resource)
      return resource.executor_program if resource.respond_to?(:executor_program)

      turn_for(resource)&.executor_program
    end

    def conversation_for(resource)
      return resource.owner_conversation if resource.is_a?(SubagentSession)
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

    def owning_agent_program_for(resource)
      return resource.agent_program if resource.respond_to?(:agent_program)

      turn_for(resource)&.agent_program_version&.agent_program ||
        conversation_for(resource)&.agent_program
    end
  end
end
