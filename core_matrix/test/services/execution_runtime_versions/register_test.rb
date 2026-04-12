require "test_helper"

module ExecutionRuntimeVersions
end

class ExecutionRuntimeVersions::RegisterTest < ActiveSupport::TestCase
  test "registers an execution runtime version, rotates the active connection, and updates the pairing session" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    pairing_session = PairingSessions::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    result = ExecutionRuntimeVersions::Register.call(
      pairing_token: pairing_session.plaintext_token,
      endpoint_metadata: {
        "transport" => "http",
        "base_url" => "https://runtime.example.test"
      },
      version_package: version_package_payload
    )

    pairing_session.reload
    agent.reload

    assert pairing_session.runtime_registered_at.present?
    assert pairing_session.last_used_at.present?
    assert_equal result.execution_runtime, agent.default_execution_runtime
    assert_equal result.execution_runtime_version, result.execution_runtime.published_execution_runtime_version
    assert_equal result.execution_runtime_version, result.execution_runtime_connection.execution_runtime_version
    assert result.execution_runtime_connection.active?
    assert_equal result.execution_runtime_connection, ExecutionRuntimeConnection.find_by_plaintext_connection_credential(result.execution_runtime_connection_credential)
    assert_equal ["exec_command"], result.execution_runtime_version.tool_catalog.map { |entry| entry.fetch("tool_name") }

    audit_log = AuditLog.find_by!(action: "execution_runtime_connection.registered")
    assert_equal result.execution_runtime_connection, audit_log.subject
  end

  test "reuses an existing runtime version when the normalized package is unchanged" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    pairing_session = PairingSessions::Issue.call(
      agent: agent,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    first = ExecutionRuntimeVersions::Register.call(
      pairing_token: pairing_session.plaintext_token,
      endpoint_metadata: { "transport" => "http", "base_url" => "https://runtime.example.test" },
      version_package: version_package_payload
    )

    second = ExecutionRuntimeVersions::Register.call(
      pairing_token: pairing_session.plaintext_token,
      endpoint_metadata: { "transport" => "http", "base_url" => "https://runtime.example.test/v2" },
      version_package: version_package_payload
    )

    assert_equal first.execution_runtime, second.execution_runtime
    assert_equal first.execution_runtime_version, second.execution_runtime_version
    assert_equal 1, first.execution_runtime.reload.execution_runtime_versions.count
    assert_equal second.execution_runtime_connection, first.execution_runtime.reload.active_execution_runtime_connection
    assert_equal "https://runtime.example.test/v2", second.execution_runtime_connection.endpoint_metadata.fetch("base_url")
  end

  private

  def version_package_payload
    {
      "execution_runtime_fingerprint" => "runtime-host-a",
      "kind" => "local",
      "protocol_version" => "agent-runtime/2026-04-01",
      "sdk_version" => "nexus-0.1.0",
      "capability_payload" => {
        "runtime_foundation" => {
          "docker_base_project" => "images/nexus"
        }
      },
      "tool_catalog" => [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "execution_runtime",
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "runtime/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort"
        }
      ],
      "reflected_host_metadata" => {
        "display_name" => "Nexus",
        "host_role" => "pairing-based execution runtime"
      }
    }
  end
end
