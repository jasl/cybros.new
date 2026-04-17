require "tempfile"
require "test_helper"

class AttachmentClientTest < Minitest::Test
  def test_refresh_attachment_posts_public_ids_and_runtime_credential
    requests = []
    client = CybrosNexus::Attachments::Client.new(
      base_url: "https://core-matrix.example.test",
      connection_credential: "runtime-secret",
      http_transport: lambda do |method:, path:, headers:, json: nil, form: nil|
        requests << { method: method, path: path, headers: headers, json: json, form: form }
        {
          status: 200,
          body: {
            "method_id" => "refresh_attachment",
            "attachment" => {
              "attachment_id" => "attachment-1",
            },
          },
        }
      end
    )

    payload = client.refresh_attachment(turn_id: "turn-1", attachment_id: "attachment-1")

    assert_equal "refresh_attachment", payload.fetch("method_id")
    assert_equal :post, requests.first.fetch(:method)
    assert_equal "/execution_runtime_api/attachments/request", requests.first.fetch(:path)
    assert_equal "turn-1", requests.first.fetch(:json).fetch("turn_id")
    assert_equal "attachment-1", requests.first.fetch(:json).fetch("attachment_id")
    assert_equal "Token token=\"runtime-secret\"", requests.first.fetch(:headers).fetch("Authorization")
  end

  def test_publish_attachment_posts_files_with_public_turn_id
    requests = []
    client = CybrosNexus::Attachments::Client.new(
      base_url: "https://core-matrix.example.test",
      connection_credential: "runtime-secret",
      http_transport: lambda do |method:, path:, headers:, json: nil, form: nil|
        requests << { method: method, path: path, headers: headers, json: json, form: form }
        {
          status: 201,
          body: {
            "method_id" => "publish_attachment",
            "attachments" => [
              {
                "attachment_id" => "attachment-1",
              },
            ],
          },
        }
      end
    )
    file = Tempfile.new(["artifact", ".txt"])
    file.write("artifact body")
    file.rewind

    payload = client.publish_attachment(
      turn_id: "turn-1",
      publication_role: "primary_deliverable",
      files: [
        {
          "io" => file,
          "filename" => "artifact.txt",
          "content_type" => "text/plain",
        },
      ]
    )

    assert_equal "publish_attachment", payload.fetch("method_id")
    assert_equal :post, requests.first.fetch(:method)
    assert_equal "/execution_runtime_api/attachments/publish", requests.first.fetch(:path)
    assert_equal "turn-1", requests.first.fetch(:form).fetch("turn_id")
    assert_equal "primary_deliverable", requests.first.fetch(:form).fetch("publication_role")
    assert_equal 1, requests.first.fetch(:form).fetch("files").length
  ensure
    file&.close!
  end
end
