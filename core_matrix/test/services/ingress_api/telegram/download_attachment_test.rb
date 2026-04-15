require "test_helper"

class IngressAPI::Telegram::DownloadAttachmentTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:body, :headers) do
    def status = 200
  end

  test "downloads a telegram file and returns a normalized attachment payload" do
    client = Class.new do
      def get_file(file_id:)
        { "file_path" => "documents/report.txt" }
      end
    end.new
    downloader = ->(_url) { FakeResponse.new("hello world", { "content-type" => "text/plain" }) }

    attachment = IngressAPI::Telegram::DownloadAttachment.call(
      client: client,
      bot_token: "telegram-bot-token",
      attachment_descriptor: {
        "file_id" => "document-1",
        "modality" => "file",
        "filename" => "report.txt"
      },
      downloader: downloader
    )

    assert_equal "report.txt", attachment.fetch("filename")
    assert_equal "text/plain", attachment.fetch("content_type")
    assert_equal "file", attachment.fetch("modality")
    assert_equal "hello world".bytesize, attachment.fetch("byte_size")
    assert_equal "hello world", attachment.fetch("io").read
  end
end
