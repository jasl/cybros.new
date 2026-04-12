class ControlPlaneChannel < ApplicationCable::Channel
  def subscribed
    if current_agent_definition_version.present?
      stream_from AgentControl::StreamName.for_agent_definition_version(current_agent_definition_version)
      AgentControl::RealtimeLinks::Open.call(
        agent_definition_version: current_agent_definition_version,
        agent_connection: current_agent_connection
      )
      return
    end

    if current_execution_runtime_connection.present?
      stream_from AgentControl::StreamName.for_execution_runtime_connection(current_execution_runtime_connection)
      AgentControl::RealtimeLinks::Open.call(
        execution_runtime_connection: current_execution_runtime_connection
      )
      return
    end

    reject
  end

  def unsubscribed
    if current_agent_definition_version.present?
      AgentControl::RealtimeLinks::Close.call(
        agent_definition_version: current_agent_definition_version,
        agent_connection: current_agent_connection
      )
      return
    end

    return if current_execution_runtime_connection.blank?

    AgentControl::RealtimeLinks::Close.call(
      execution_runtime_connection: current_execution_runtime_connection
    )
  end
end
