require "stringio"

module IngressAPI
  module Telegram
    class DownloadAttachment
      def self.call(...)
        new(...).call
      end

      def initialize(client:, attachment_descriptor:, bot_token:, downloader: nil)
        @client = client
        @attachment_descriptor = attachment_descriptor.deep_stringify_keys
        @bot_token = bot_token
        @downloader = downloader
      end

      def call
        file = @client.get_file(file_id: @attachment_descriptor.fetch("file_id"))
        file_path = file.fetch("file_path")
        response = downloader.call(download_url(file_path))
        body = response.body.to_s
        filename = @attachment_descriptor["filename"].presence || File.basename(file_path)
        content_type = response.headers["content-type"].presence || Marcel::MimeType.for(StringIO.new(body), name: filename)

        {
          "file_id" => @attachment_descriptor.fetch("file_id"),
          "filename" => filename,
          "content_type" => content_type,
          "byte_size" => body.bytesize,
          "modality" => @attachment_descriptor.fetch("modality"),
          "io" => StringIO.new(body),
          "transport_metadata" => {
            "file_path" => file_path,
          },
        }
      end

      private

      def download_url(file_path)
        IngressAPI::Telegram::Client.new(bot_token: @bot_token).file_download_url(file_path)
      end

      def downloader
        @downloader ||= ->(url) { HTTPX.get(url) }
      end
    end
  end
end
