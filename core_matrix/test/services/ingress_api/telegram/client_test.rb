require "test_helper"

class IngressAPI::Telegram::ClientTest < ActiveSupport::TestCase
  BotSpy = Struct.new(:calls) do
    def send_message(**kwargs)
      calls << [:send_message, kwargs]
      { "message_id" => 101, "chat" => { "id" => kwargs.fetch(:chat_id) } }
    end

    def edit_message_text(**kwargs)
      calls << [:edit_message_text, kwargs]
      { "message_id" => kwargs.fetch(:message_id), "chat" => { "id" => kwargs.fetch(:chat_id) } }
    end

    def get_file(**kwargs)
      calls << [:get_file, kwargs]
      { "file_path" => "photos/file.jpg" }
    end
  end

  test "delegates bot api calls to the wrapped telegram bot client" do
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)

    client.send_message(chat_id: 42, text: "hello")
    client.edit_message_text(chat_id: 42, message_id: 99, text: "updated")
    file = client.get_file(file_id: "photo-1")

    assert_equal [
      [:send_message, { chat_id: 42, text: "hello" }],
      [:edit_message_text, { chat_id: 42, message_id: 99, text: "updated" }],
      [:get_file, { file_id: "photo-1" }],
    ], bot.calls
    assert_equal "photos/file.jpg", file.fetch("file_path")
  end

  test "builds bot api download urls from the bot token and file path" do
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: BotSpy.new([]))

    assert_equal(
      "https://api.telegram.org/file/bottelegram-bot-token/photos/file.jpg",
      client.file_download_url("photos/file.jpg")
    )
  end
end
