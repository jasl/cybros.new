module ChannelConnectors
  class DispatchActivePollersJob < ApplicationJob
    queue_as :maintenance

    def perform
      ChannelConnector.where(lifecycle_state: "active", transport_kind: "poller").find_each do |channel_connector|
        next unless channel_connector.poller_ready?

        dispatch_poll_job(channel_connector)
      end
    end

    private

    def dispatch_poll_job(channel_connector)
      case channel_connector.platform
      when "telegram"
        ChannelConnectors::TelegramPollUpdatesJob.perform_later(channel_connector.public_id)
      when "weixin"
        ChannelConnectors::WeixinPollAccountJob.perform_later(channel_connector.public_id)
      end
    end
  end
end
