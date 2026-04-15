module ChannelConnectors
  class WeixinPollAccountJob < ApplicationJob
    queue_as :default

    def perform(channel_connector_public_id, poller: ClawBotSDK::Weixin::Poller, receiver: IngressAPI::Weixin::ReceivePolledMessage)
      channel_connector = ChannelConnector.find_by!(
        public_id: channel_connector_public_id,
        platform: "weixin"
      )
      return unless channel_connector.active?

      poller.call(channel_connector: channel_connector).each do |message|
        receiver.call(channel_connector: channel_connector, message: message)
      end
    end
  end
end
