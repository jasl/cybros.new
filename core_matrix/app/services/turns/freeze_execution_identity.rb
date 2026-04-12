module Turns
  class FreezeExecutionIdentity
    ExecutionIdentity = Struct.new(
      :agent_definition_version,
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
      agent_connection = AgentConnection.find_by(agent: @conversation.agent, lifecycle_state: "active")
      unless agent_connection.present?
        @conversation.errors.add(:agent, "must have an active agent connection for turn entry")
        raise ActiveRecord::RecordInvalid, @conversation
      end

      execution_runtime = resolve_execution_runtime
      execution_runtime_version = resolve_execution_runtime_version(execution_runtime)

      ExecutionIdentity.new(
        agent_definition_version: agent_connection.agent_definition_version,
        execution_runtime: execution_runtime,
        execution_runtime_version: execution_runtime_version,
        agent_config_state: @conversation.agent.agent_config_state
      )
    end

    private

    def resolve_execution_runtime
      Turns::SelectExecutionRuntime.call(
        conversation: @conversation,
        execution_runtime: @requested_execution_runtime
      )
    rescue ActiveRecord::RecordInvalid
      raise unless @allow_unavailable_execution_runtime

      nil
    end

    def resolve_execution_runtime_version(execution_runtime)
      return nil if execution_runtime.blank?

      execution_runtime.current_execution_runtime_version || begin
        @conversation.errors.add(:execution_runtime, "must have an active execution runtime version for turn entry")
        raise ActiveRecord::RecordInvalid, @conversation unless @allow_unavailable_execution_runtime
      end
    end
  end
end
