require "base64"
require "cgi"
require "digest"
require "openssl"
require "securerandom"

module ClawBotSDK
  module Weixin
    class MediaClient
      UploadConfigurationError = Class.new(StandardError)
      CdnUploadError = Class.new(StandardError) do
        attr_reader :retryable

        def initialize(message, retryable:)
          @retryable = retryable
          super(message)
        end
      end

      UPLOAD_MAX_RETRIES = 3

      def initialize(client:, upload_client: nil, aes_key_generator: nil, filekey_generator: nil)
        @client = client
        @upload_client = upload_client || method(:default_upload_client)
        @aes_key_generator = aes_key_generator || -> { SecureRandom.random_bytes(16) }
        @filekey_generator = filekey_generator || -> { SecureRandom.hex(16) }
      end

      def send_attachment(attachment_record:, descriptor:, to_user_id:, context_token:, text: nil)
        upload = upload_attachment(
          attachment_record: attachment_record,
          descriptor: descriptor,
          to_user_id: to_user_id
        )

        @client.send_message(
          to_user_id: to_user_id,
          context_token: context_token,
          item_list: [text_item(text)]
        ) if text.present?

        @client.send_message(
          to_user_id: to_user_id,
          context_token: context_token,
          item_list: [media_item(descriptor: descriptor, attachment_record: attachment_record, upload: upload)]
        )
      end

      private

      def upload_attachment(attachment_record:, descriptor:, to_user_id:)
        plaintext = attachment_record.file.download.b
        aes_key = @aes_key_generator.call
        filekey = @filekey_generator.call.to_s
        upload_request = build_upload_request(
          attachment_record: attachment_record,
          descriptor: descriptor,
          to_user_id: to_user_id,
          plaintext: plaintext,
          aes_key: aes_key,
          filekey: filekey
        )
        upload_response = @client.get_upload_url(upload_request).deep_stringify_keys
        upload_url = resolve_upload_url(upload_response: upload_response, filekey: filekey)
        ciphertext = encrypt_aes_ecb(plaintext, aes_key)
        download_param = upload_ciphertext(upload_url: upload_url, ciphertext: ciphertext)

        {
          download_param: download_param,
          aes_key: aes_key,
          file_size: plaintext.bytesize,
          ciphertext_size: ciphertext.bytesize,
        }
      end

      def build_upload_request(attachment_record:, descriptor:, to_user_id:, plaintext:, aes_key:, filekey:)
        {
          "filekey" => filekey,
          "media_type" => upload_media_type(descriptor, attachment_record),
          "to_user_id" => to_user_id,
          "rawsize" => plaintext.bytesize,
          "rawfilemd5" => Digest::MD5.hexdigest(plaintext),
          "filesize" => aes_ecb_padded_size(plaintext.bytesize),
          "no_need_thumb" => true,
          "aeskey" => aes_key.unpack1("H*"),
        }
      end

      def resolve_upload_url(upload_response:, filekey:)
        full_url = upload_response["upload_full_url"].to_s.strip
        return full_url if full_url.present?

        upload_param = upload_response["upload_param"].to_s
        cdn_base_url = @client.respond_to?(:cdn_base_url) ? @client.cdn_base_url.to_s.strip : ""
        if upload_param.blank? || cdn_base_url.blank?
          raise UploadConfigurationError,
            "weixin native attachment delivery requires upload_full_url or upload_param plus cdn_base_url"
        end

        "#{cdn_base_url.sub(%r{/+\z}, "")}/upload?encrypted_query_param=#{CGI.escape(upload_param)}&filekey=#{CGI.escape(filekey)}"
      end

      def upload_ciphertext(upload_url:, ciphertext:)
        attempts = 0

        begin
          attempts += 1
          response = @upload_client.call(
            url: upload_url,
            body: ciphertext,
            headers: { "Content-Type" => "application/octet-stream" }
          )
          download_param = extract_download_param(response)
          raise CdnUploadError.new("weixin CDN upload response missing download param", retryable: false) if download_param.blank?

          download_param
        rescue CdnUploadError => error
          raise unless error.retryable && attempts < UPLOAD_MAX_RETRIES
          retry
        rescue StandardError
          raise if attempts >= UPLOAD_MAX_RETRIES
          retry
        end
      end

      def extract_download_param(response)
        if response.is_a?(Hash)
          payload = response.deep_stringify_keys
          payload["download_param"].presence || payload["x-encrypted-param"].presence
        elsif response.respond_to?(:headers)
          response.headers["x-encrypted-param"].presence || response.headers["X-Encrypted-Param"].presence
        end
      end

      def media_item(descriptor:, attachment_record:, upload:)
        media_payload = {
          "encrypt_query_param" => upload.fetch(:download_param),
          "aes_key" => Base64.strict_encode64(upload.fetch(:aes_key)),
          "encrypt_type" => 1,
        }

        case resolved_modality(descriptor, attachment_record)
        when "image"
          {
            "type" => 2,
            "image_item" => {
              "media" => media_payload,
              "mid_size" => upload.fetch(:ciphertext_size),
            },
          }
        when "video"
          {
            "type" => 5,
            "video_item" => {
              "media" => media_payload,
              "video_size" => upload.fetch(:ciphertext_size),
            },
          }
        else
          {
            "type" => 4,
            "file_item" => {
              "media" => media_payload,
              "file_name" => descriptor["filename"].presence || attachment_record.file.filename.to_s,
              "len" => upload.fetch(:file_size).to_s,
            },
          }
        end
      end

      def resolved_modality(descriptor, attachment_record)
        descriptor["modality"].presence || begin
          content_type = attachment_record.file.blob.content_type.to_s
          if content_type.start_with?("image/")
            "image"
          elsif content_type.start_with?("video/")
            "video"
          else
            "file"
          end
        end
      end

      def upload_media_type(descriptor, attachment_record)
        case resolved_modality(descriptor, attachment_record)
        when "image" then 1
        when "video" then 2
        else 3
        end
      end

      def text_item(text)
        {
          "type" => 1,
          "text_item" => { "text" => text },
        }
      end

      def encrypt_aes_ecb(plaintext, key)
        cipher = OpenSSL::Cipher.new("aes-128-ecb")
        cipher.encrypt
        cipher.key = key
        cipher.padding = 1
        cipher.update(plaintext) + cipher.final
      end

      def aes_ecb_padded_size(plaintext_size)
        (((plaintext_size + 1) + 15) / 16) * 16
      end

      def default_upload_client(url:, body:, headers:)
        response = HTTPX.post(url, headers:, body:)
        status = response.status.to_i
        if status >= 400 && status < 500
          error_message = response.headers["x-error-message"].presence || response.to_s
          raise CdnUploadError.new("weixin CDN upload client error #{status}: #{error_message}", retryable: false)
        end
        if status != 200
          error_message = response.headers["x-error-message"].presence || "status #{status}"
          raise CdnUploadError.new("weixin CDN upload server error #{status}: #{error_message}", retryable: true)
        end

        response
      end
    end
  end
end
