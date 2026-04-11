class ControlPlaneChannel < ApplicationCable::Channel
  def subscribed
    if current_agent_snapshot.present?
      stream_from AgentControl::StreamName.for_agent_snapshot(current_agent_snapshot)
      AgentControl::RealtimeLinks::Open.call(
        agent_snapshot: current_agent_snapshot,
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
    if current_agent_snapshot.present?
      AgentControl::RealtimeLinks::Close.call(
        agent_snapshot: current_agent_snapshot,
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
