module Turns
  class FreezeExecutionIdentity
    ExecutionIdentity = Struct.new(
      :agent_definition_version,
      :execution_epoch,
      :execution_runtime,
      :execution_runtime_version,
      :agent_config_state,
      keyword_init: true
    ) do
      def pinned_agent_definition_fingerprint
        agent_definition_version.definition_fingerprint
      end

      def agent_config_version
        agent_config_state&.version || 1
      end

      def agent_config_content_fingerprint
        agent_config_state&.content_fingerprint || agent_definition_version.definition_fingerprint
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, execution_runtime: nil, allow_unavailable_execution_runtime: false)
      @conversation = conversation
      @requested_execution_runtime = execution_runtime
      @allow_unavailable_execution_runtime = allow_unavailable_execution_runtime
    end

    def call
      execution_runtime = resolve_execution_runtime
      execution_epoch = resolve_execution_epoch(execution_runtime)
      execution_context = Conversations::ResolveExecutionContext.call(
        conversation: @conversation,
        execution_runtime: @requested_execution_runtime,
        selected_execution_runtime: execution_runtime,
        allow_unavailable_execution_runtime: @allow_unavailable_execution_runtime
      )
      agent_config_state = AgentConfigState.find_by(agent_id: @conversation.agent_id)

      ExecutionIdentity.new(
        agent_definition_version: execution_context.agent_definition_version,
        execution_epoch: execution_epoch,
        execution_runtime: execution_context.execution_runtime,
        execution_runtime_version: execution_context.execution_runtime_version,
        agent_config_state: agent_config_state
      )
    end

    private

    def resolve_execution_runtime
      if @requested_execution_runtime.present?
        return @requested_execution_runtime if @conversation.current_execution_epoch.blank?
        return @requested_execution_runtime if @requested_execution_runtime == @conversation.current_execution_runtime

        if @conversation.turns.exists?
          @conversation.errors.add(:base, "conversation runtime handoff is not implemented yet")
          raise ActiveRecord::RecordInvalid, @conversation unless @allow_unavailable_execution_runtime

          return @requested_execution_runtime
        end

        ConversationExecutionEpochs::RetargetCurrent.call(
          conversation: @conversation,
          execution_runtime: @requested_execution_runtime
        )
        return @requested_execution_runtime
      end

      Turns::SelectExecutionRuntime.call(
        conversation: @conversation
      )
    rescue ActiveRecord::RecordInvalid
      raise unless @allow_unavailable_execution_runtime

      nil
    end

    def resolve_execution_epoch(execution_runtime)
      return @conversation.current_execution_epoch if @conversation.current_execution_epoch.present?

      ConversationExecutionEpochs::InitializeCurrent.call(
        conversation: @conversation,
        execution_runtime: execution_runtime || @requested_execution_runtime
      )
    end
  end
end
