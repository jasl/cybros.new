class AgentControlChannel < ApplicationCable::Channel
  def subscribed
    stream_from AgentControl::StreamName.for_deployment(current_deployment)
    AgentControl::RealtimeLinks::Open.call(deployment: current_deployment)
  end

  def unsubscribed
    AgentControl::RealtimeLinks::Close.call(deployment: current_deployment)
  end
end
