class AgentControlChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_deployment.present?

    stream_from AgentControl::StreamName.for_deployment(current_deployment)
    AgentControl::RealtimeLinks::Open.call(deployment: current_deployment)
  end

  def unsubscribed
    return if current_deployment.blank?

    AgentControl::RealtimeLinks::Close.call(deployment: current_deployment)
  end
end
