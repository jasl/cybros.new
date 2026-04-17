require "test_helper"

class SessionClientTest < Minitest::Test
  def test_open_session_posts_version_package_and_persists_runtime_session
    requests = []
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))

    client = CybrosNexus::Session::Client.new(
      base_url: "https://core-matrix.example.test",
      store: store,
      http_transport: lambda do |method:, path:, headers:, json:|
        requests << { method: method, path: path, headers: headers, json: json }

        {
          status: 201,
          body: {
            "method_id" => "execution_runtime_session_open",
            "execution_runtime_connection_id" => "erc_123",
            "execution_runtime_connection_credential" => "secret-credential",
            "execution_runtime_fingerprint" => "runtime-host-a",
            "transport_hints" => {
              "mailbox" => { "pull_path" => "/execution_runtime_api/mailbox/pull" },
              "events" => { "batch_path" => "/execution_runtime_api/events/batch" },
            },
          },
        }
      end
    )

    payload = client.open_session(
      onboarding_token: "onboard-123",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4040",
      },
      version_package: version_package
    )

    assert_equal "execution_runtime_session_open", payload.fetch("method_id")
    assert_equal "secret-credential", client.connection_credential
    assert_equal :post, requests.first.fetch(:method)
    assert_equal "/execution_runtime_api/session/open", requests.first.fetch(:path)
    assert_nil requests.first.fetch(:headers)["Authorization"]
    assert_equal "onboard-123", requests.first.fetch(:json).fetch("onboarding_token")

    row = store.database.get_first_row(
      "SELECT session_id, credential, version_fingerprint FROM runtime_sessions"
    )
    assert_equal ["erc_123", "secret-credential", "runtime-host-a"], row
  ensure
    store&.close
  end

  def test_refresh_session_uses_saved_runtime_credential
    requests = []
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))

    client = CybrosNexus::Session::Client.new(
      base_url: "https://core-matrix.example.test",
      store: store,
      http_transport: lambda do |method:, path:, headers:, json:|
        requests << { method: method, path: path, headers: headers, json: json }

        if path == "/execution_runtime_api/session/open"
          {
            status: 201,
            body: {
              "method_id" => "execution_runtime_session_open",
              "execution_runtime_connection_id" => "erc_123",
              "execution_runtime_connection_credential" => "secret-credential",
              "execution_runtime_fingerprint" => "runtime-host-a",
              "transport_hints" => {
                "mailbox" => { "pull_path" => "/execution_runtime_api/mailbox/pull" },
                "events" => { "batch_path" => "/execution_runtime_api/events/batch" },
              },
            },
          }
        else
          {
            status: 200,
            body: {
              "method_id" => "execution_runtime_session_refresh",
              "execution_runtime_connection_id" => "erc_123",
              "execution_runtime_fingerprint" => "runtime-host-a",
              "transport_hints" => {
                "mailbox" => { "pull_path" => "/execution_runtime_api/mailbox/pull" },
                "events" => { "batch_path" => "/execution_runtime_api/events/batch" },
              },
            },
          }
        end
      end
    )

    client.open_session(
      onboarding_token: "onboard-123",
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "http://127.0.0.1:4040",
      },
      version_package: version_package
    )

    payload = client.refresh_session(version_package: version_package)

    assert_equal "execution_runtime_session_refresh", payload.fetch("method_id")
    assert_equal "Token token=\"secret-credential\"", requests.last.fetch(:headers).fetch("Authorization")
    assert_equal "/execution_runtime_api/session/refresh", requests.last.fetch(:path)
  ensure
    store&.close
  end

  private

  def version_package
    {
      "execution_runtime_fingerprint" => "runtime-host-a",
      "kind" => "local",
      "protocol_version" => "agent-runtime/2026-04-01",
      "sdk_version" => "nexus-0.1.0",
      "capability_payload" => {
        "runtime_foundation" => {
          "docker_base_project" => "images/nexus",
        },
      },
      "tool_catalog" => [],
      "reflected_host_metadata" => {
        "display_name" => "Nexus",
      },
    }
  end
end
