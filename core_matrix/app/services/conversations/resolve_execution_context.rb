module Conversations
  class ResolveExecutionContext
    UNSET_RUNTIME = Object.new.freeze

    ExecutionContext = Struct.new(
      :agent_definition_version,
      :execution_runtime,
      :execution_runtime_version,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, execution_runtime: nil, selected_execution_runtime: UNSET_RUNTIME, allow_unavailable_execution_runtime: false)
      @conversation = conversation
      @requested_execution_runtime = execution_runtime
      @selected_execution_runtime = selected_execution_runtime
      @allow_unavailable_execution_runtime = allow_unavailable_execution_runtime
    end

    def call
      ExecutionContext.new(
        agent_definition_version: agent_connection.agent_definition_version,
        execution_runtime: execution_runtime,
        execution_runtime_version: execution_runtime_version
      )
    end

    private

    def agent_connection
      @agent_connection ||= AgentConnection.find_by(agent_id: @conversation.agent_id, lifecycle_state: "active") || begin
        @conversation.errors.add(:agent, "must have an active agent connection for turn entry")
        raise ActiveRecord::RecordInvalid, @conversation
      end
    end

    def execution_runtime
      return @selected_execution_runtime unless @selected_execution_runtime.equal?(UNSET_RUNTIME)

      @execution_runtime ||= Turns::SelectExecutionRuntime.call(
        conversation: @conversation,
        execution_runtime: @requested_execution_runtime
      )
    rescue ActiveRecord::RecordInvalid
      raise unless @allow_unavailable_execution_runtime

      nil
    end

    def execution_runtime_version
      runtime = execution_runtime
      return nil if runtime.blank?

      runtime.current_execution_runtime_version ||
        ExecutionRuntime.find_by(id: runtime.id)&.current_execution_runtime_version || begin
          @conversation.errors.add(:execution_runtime, "must have an active execution runtime version for turn entry")
          raise ActiveRecord::RecordInvalid, @conversation unless @allow_unavailable_execution_runtime
        end
    end
  end
end
