require "test_helper"

class ClawBotSDK::Weixin::ClientTest < ActiveSupport::TestCase
  test "posts getupdates with the cached cursor and parses the response" do
    request = nil
    client = ClawBotSDK::Weixin::Client.new(
      base_url: "https://weixin.example",
      bot_token: "bot-token",
      http_client: lambda do |**kwargs|
        request = kwargs
        {
          "ret" => 0,
          "msgs" => [],
          "get_updates_buf" => "cursor-2"
        }
      end
    )

    response = client.get_updates(get_updates_buf: "cursor-1")

    assert_equal "POST", request[:method]
    assert_equal "ilink/bot/getupdates", request[:endpoint]
    assert_equal "bot-token", request[:token]
    assert_equal "cursor-1", request[:body]["get_updates_buf"]
    assert_predicate request[:body]["base_info"], :present?
    assert_equal "cursor-2", response.fetch("get_updates_buf")
  end

  test "posts text sends to sendmessage with the supplied context token" do
    request = nil
    client = ClawBotSDK::Weixin::Client.new(
      base_url: "https://weixin.example",
      bot_token: "bot-token",
      http_client: lambda do |**kwargs|
        request = kwargs
        { "ret" => 0, "message_id" => "wx-msg-1" }
      end
    )

    response = client.send_text(
      to_user_id: "wx-user-1",
      text: "hello from core matrix",
      context_token: "ctx-1"
    )

    assert_equal "ilink/bot/sendmessage", request[:endpoint]
    assert_equal "hello from core matrix", request.dig(:body, "msg", "item_list", 0, "text_item", "text")
    assert_equal "ctx-1", request.dig(:body, "msg", "context_token")
    assert_equal "wx-msg-1", response.fetch("message_id")
  end

  test "posts sendtyping with the supplied typing ticket" do
    request = nil
    client = ClawBotSDK::Weixin::Client.new(
      base_url: "https://weixin.example",
      bot_token: "bot-token",
      http_client: lambda do |**kwargs|
        request = kwargs
        { "ret" => 0 }
      end
    )

    client.send_typing(
      ilink_user_id: "wx-user-1",
      typing_ticket: "typing-ticket-1"
    )

    assert_equal "ilink/bot/sendtyping", request[:endpoint]
    assert_equal "wx-user-1", request[:body]["ilink_user_id"]
    assert_equal "typing-ticket-1", request[:body]["typing_ticket"]
    assert_predicate request[:body]["base_info"], :present?
  end
end
