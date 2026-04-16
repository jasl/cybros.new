require "test_helper"

class ChannelConnectors::TelegramPollUpdatesJobTest < ActiveJob::TestCase
  FakeTelegramClient = Struct.new(:calls, :updates, keyword_init: true) do
    def delete_webhook(drop_pending_updates:)
      calls << [:delete_webhook, drop_pending_updates]
    end

    def get_updates(offset:, timeout:)
      calls << [:get_updates, offset, timeout]
      updates
    end
  end

  test "clears webhook mode, polls updates, dispatches them, and advances the durable offset" do
    connector = create_telegram_connector!(
      runtime_state_payload: {
        "telegram_update_offset" => 100,
      }
    )
    client = FakeTelegramClient.new(
      calls: [],
      updates: [
        {
          "update_id" => 101,
          "message" => {
            "message_id" => 51,
            "date" => 1_713_612_345,
            "chat" => { "id" => 42, "type" => "private" },
            "from" => { "id" => 42, "username" => "alice" },
            "text" => "hello",
          },
        },
        {
          "update_id" => 103,
          "message" => {
            "message_id" => 52,
            "date" => 1_713_612_346,
            "chat" => { "id" => 42, "type" => "private" },
            "from" => { "id" => 42, "username" => "alice" },
            "text" => "hello again",
          },
        },
      ]
    )
    receiver_calls = []
    fake_receiver = lambda do |channel_connector:, update:|
      receiver_calls << [channel_connector.public_id, update.fetch("update_id")]
    end

    ChannelConnectors::TelegramPollUpdatesJob.perform_now(
      connector.public_id,
      client_factory: ->(channel_connector:) { client },
      receiver: fake_receiver
    )

    assert_equal [
      [:delete_webhook, false],
      [:get_updates, 100, 20],
    ], client.calls
    assert_equal [
      [connector.public_id, 101],
      [connector.public_id, 103],
    ], receiver_calls
    assert_equal 104, connector.reload.runtime_state_payload.fetch("telegram_update_offset")
  end

  private

  def create_telegram_connector!(runtime_state_payload: {})
    context = create_workspace_context!
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )

    ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Telegram Poller",
      lifecycle_state: "active",
      credential_ref_payload: { "bot_token" => "123:abc" },
      config_payload: {},
      runtime_state_payload: runtime_state_payload
    )
  end
end
