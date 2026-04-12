module AgentControl
  class StreamName
    def self.for_agent_definition_version(agent_definition_version)
      "agent_control:agent_definition_version:#{agent_definition_version.public_id}"
    end

    def self.for_execution_runtime_connection(execution_runtime_connection)
      "agent_control:execution_runtime_connection:#{execution_runtime_connection.public_id}"
    end

    def self.for_delivery_endpoint(delivery_endpoint)
      case delivery_endpoint
      when AgentDefinitionVersion
        for_agent_definition_version(delivery_endpoint)
      when ExecutionRuntimeConnection
        for_execution_runtime_connection(delivery_endpoint)
      else
        raise ArgumentError, "unsupported realtime delivery endpoint #{delivery_endpoint.inspect}"
      end
    end
  end
end
