require "test_helper"

class AgentConnectionTest < ActiveSupport::TestCase
  test "allows only one active connection per agent" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    first_version = create_agent_definition_version!(installation: installation, agent: agent)
    second_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      version: 2,
      definition_fingerprint: "version-#{next_test_sequence}"
    )

    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: first_version,
      lifecycle_state: "active"
    )

    conflicting = AgentConnection.new(
      installation: installation,
      agent: agent,
      agent_definition_version: second_version,
      connection_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      connection_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    assert_not conflicting.valid?
    assert_includes conflicting.errors[:agent_id], "already has an active connection"
  end
end
