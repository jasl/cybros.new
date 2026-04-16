module ChannelConnectors
  class TelegramPollUpdatesJob < ApplicationJob
    DEFAULT_POLL_TIMEOUT_SECONDS = 20

    queue_as :default

    def perform(channel_connector_public_id, client_factory: nil, receiver: IngressAPI::Telegram::ReceivePolledUpdate)
      channel_connector = ChannelConnector.find_by!(
        public_id: channel_connector_public_id,
        platform: "telegram",
        transport_kind: "poller"
      )

      channel_connector.with_lock do
        channel_connector.reload
        return unless channel_connector.poller_ready?

        client = build_client(channel_connector, client_factory)
        client.delete_webhook(drop_pending_updates: false)

        updates = Array(
          client.get_updates(
            offset: current_update_offset(channel_connector),
            timeout: poll_timeout_seconds(channel_connector)
          )
        ).map { |update| update.respond_to?(:deep_stringify_keys) ? update.deep_stringify_keys : update }

        updates.each do |update|
          receiver.call(channel_connector: channel_connector, update: update)
        end

        persist_update_offset!(channel_connector, updates)
      end
    end

    private

    def build_client(channel_connector, client_factory)
      return client_factory.call(channel_connector: channel_connector) if client_factory.respond_to?(:call)

      IngressAPI::Telegram::Client.for_channel_connector(channel_connector)
    end

    def current_update_offset(channel_connector)
      channel_connector.runtime_state_payload["telegram_update_offset"].to_i
    end

    def poll_timeout_seconds(channel_connector)
      configured_timeout = channel_connector.config_payload["poll_timeout_seconds"].to_i
      configured_timeout.positive? ? configured_timeout : DEFAULT_POLL_TIMEOUT_SECONDS
    end

    def persist_update_offset!(channel_connector, updates)
      max_update_id = updates.filter_map { |update| update["update_id"] }.max
      return if max_update_id.blank?

      channel_connector.update!(
        runtime_state_payload: channel_connector.runtime_state_payload.deep_stringify_keys.merge(
          "telegram_update_offset" => max_update_id.to_i + 1
        )
      )
    end
  end
end
