require "test_helper"

class Conversations::Metadata::BuildManagedChannelTitleTest < ActiveSupport::TestCase
  test "builds telegram dm title from username when available" do
    title = Conversations::Metadata::BuildManagedChannelTitle.call(
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      session_metadata: { "sender_username" => "alice" }
    )

    assert_equal "Telegram DM @alice", title
  end

  test "builds telegram dm title from peer id when username is absent" do
    title = Conversations::Metadata::BuildManagedChannelTitle.call(
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "123456789",
      session_metadata: {}
    )

    assert_equal "Telegram DM 123456789", title
  end

  test "builds telegram webhook dm title from username when available" do
    title = Conversations::Metadata::BuildManagedChannelTitle.call(
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "42",
      session_metadata: { "sender_username" => "alice" }
    )

    assert_equal "Telegram Webhook DM @alice", title
  end

  test "builds telegram webhook dm title from peer id when username is absent" do
    title = Conversations::Metadata::BuildManagedChannelTitle.call(
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "123456789",
      session_metadata: {}
    )

    assert_equal "Telegram Webhook DM 123456789", title
  end
end
