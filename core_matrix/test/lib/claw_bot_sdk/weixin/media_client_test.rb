require "test_helper"

class ClawBotSDK::Weixin::MediaClientTest < ActiveSupport::TestCase
  test "uploads image attachments and sends caption plus native image item" do
    attachment = create_attachment!(filename: "sample.png", content_type: "image/png", body: "png-body")
    upload_requests = []
    send_requests = []
    upload_call = nil
    client = build_client(
      upload_requests: upload_requests,
      send_requests: send_requests,
      get_upload_url_response: { "upload_full_url" => "https://cdn.example/upload/direct" }
    )
    media_client = ClawBotSDK::Weixin::MediaClient.new(
      client: client,
      upload_client: lambda do |url:, body:, headers:|
        upload_call = [url, body, headers]
        { "download_param" => "encrypted-download-1" }
      end,
      aes_key_generator: -> { ("\x01" * 16).b },
      filekey_generator: -> { "file-key-1" }
    )

    response = media_client.send_attachment(
      attachment_record: attachment,
      descriptor: {
        "attachment_id" => attachment.public_id,
        "filename" => "sample.png",
        "modality" => "image",
      },
      to_user_id: "wx-user-1",
      context_token: "ctx-1",
      text: "caption"
    )

    assert_equal 1, upload_requests.length
    assert_equal "file-key-1", upload_requests.first["filekey"]
    assert_equal 1, upload_requests.first["media_type"]
    assert_equal attachment.file.blob.byte_size, upload_requests.first["rawsize"]
    assert_equal Digest::MD5.hexdigest("png-body"), upload_requests.first["rawfilemd5"]
    assert_equal 16, upload_requests.first["filesize"]
    assert_equal "01010101010101010101010101010101", upload_requests.first["aeskey"]

    assert_equal "https://cdn.example/upload/direct", upload_call.first
    assert_equal({ "Content-Type" => "application/octet-stream" }, upload_call.third)
    assert_equal 16, upload_call.second.bytesize

    assert_equal 2, send_requests.length
    assert_equal "caption", send_requests.first.dig(1, 0, "text_item", "text")
    assert_equal 2, send_requests.second.dig(1, 0, "type")
    assert_equal "encrypted-download-1", send_requests.second.dig(1, 0, "image_item", "media", "encrypt_query_param")
    assert_equal Base64.strict_encode64(("\x01" * 16).b), send_requests.second.dig(1, 0, "image_item", "media", "aes_key")
    assert_equal 16, send_requests.second.dig(1, 0, "image_item", "mid_size")
    assert_equal "wx-msg-2", response.fetch("message_id")
  end

  test "builds fallback CDN upload URLs from upload_param for file attachments" do
    attachment = create_attachment!(filename: "artifact.txt", content_type: "text/plain", body: "small body")
    send_requests = []
    upload_call = nil
    client = build_client(
      upload_requests: [],
      send_requests: send_requests,
      cdn_base_url: "https://cdn.example",
      get_upload_url_response: { "upload_param" => "encrypted-upload-1" }
    )
    media_client = ClawBotSDK::Weixin::MediaClient.new(
      client: client,
      upload_client: lambda do |url:, body:, headers:|
        upload_call = [url, body, headers]
        { "download_param" => "encrypted-download-2" }
      end,
      aes_key_generator: -> { ("\x02" * 16).b },
      filekey_generator: -> { "file-key-2" }
    )

    media_client.send_attachment(
      attachment_record: attachment,
      descriptor: {
        "attachment_id" => attachment.public_id,
        "filename" => "artifact.txt",
        "modality" => "file",
      },
      to_user_id: "wx-user-1",
      context_token: "ctx-1"
    )

    assert_equal "https://cdn.example/upload?encrypted_query_param=encrypted-upload-1&filekey=file-key-2", upload_call.first
    assert_equal({ "Content-Type" => "application/octet-stream" }, upload_call.third)
    assert_equal 1, send_requests.length
    assert_equal 4, send_requests.first.dig(1, 0, "type")
    assert_equal "artifact.txt", send_requests.first.dig(1, 0, "file_item", "file_name")
    assert_equal attachment.file.blob.byte_size.to_s, send_requests.first.dig(1, 0, "file_item", "len")
    assert_equal "encrypted-download-2", send_requests.first.dig(1, 0, "file_item", "media", "encrypt_query_param")
  end

  test "raises when native upload is selected but no CDN upload URL can be resolved" do
    attachment = create_attachment!
    client = build_client(
      upload_requests: [],
      send_requests: [],
      get_upload_url_response: { "upload_param" => "encrypted-upload-1" }
    )
    media_client = ClawBotSDK::Weixin::MediaClient.new(client: client)

    error = assert_raises(ClawBotSDK::Weixin::MediaClient::UploadConfigurationError) do
      media_client.send_attachment(
        attachment_record: attachment,
        descriptor: {
          "attachment_id" => attachment.public_id,
          "filename" => attachment.file.filename.to_s,
          "modality" => "file",
        },
        to_user_id: "wx-user-1",
        context_token: "ctx-1"
      )
    end

    assert_includes error.message, "cdn_base_url"
  end

  private

  def build_client(upload_requests:, send_requests:, get_upload_url_response:, cdn_base_url: nil)
    Class.new do
      attr_reader :cdn_base_url

      define_method(:initialize) do |upload_requests:, send_requests:, get_upload_url_response:, cdn_base_url:|
        @upload_requests = upload_requests
        @send_requests = send_requests
        @get_upload_url_response = get_upload_url_response
        @cdn_base_url = cdn_base_url
      end

      define_method(:get_upload_url) do |payload|
        @upload_requests << payload.deep_stringify_keys
        @get_upload_url_response.deep_stringify_keys
      end

      define_method(:send_message) do |to_user_id:, item_list:, context_token:|
        @send_requests << [to_user_id, Array(item_list).map(&:deep_stringify_keys), context_token]
        { "message_id" => "wx-msg-#{@send_requests.length}" }
      end
    end.new(
      upload_requests: upload_requests,
      send_requests: send_requests,
      get_upload_url_response: get_upload_url_response,
      cdn_base_url: cdn_base_url
    )
  end

  def create_attachment!(filename: "attachment.txt", content_type: "text/plain", body: "attachment body")
    context = create_workspace_context!
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output_message = attach_selected_output!(turn, content: "output")

    create_message_attachment!(
      message: output_message,
      filename: filename,
      content_type: content_type,
      body: body,
      identify: false
    )
  end
end
