require "test_helper"

class AgentSessionTest < ActiveSupport::TestCase
  test "allows only one active session per agent program" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    first_version = create_agent_program_version!(installation: installation, agent_program: agent_program)
    second_version = create_agent_program_version!(
      installation: installation,
      agent_program: agent_program,
      fingerprint: "version-#{next_test_sequence}"
    )

    create_agent_session!(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: first_version,
      lifecycle_state: "active"
    )

    conflicting = AgentSession.new(
      installation: installation,
      agent_program: agent_program,
      agent_program_version: second_version,
      session_credential_digest: Digest::SHA256.hexdigest("credential-#{next_test_sequence}"),
      session_token_digest: Digest::SHA256.hexdigest("token-#{next_test_sequence}"),
      endpoint_metadata: {},
      lifecycle_state: "active"
    )

    assert_not conflicting.valid?
    assert_includes conflicting.errors[:agent_program_id], "already has an active session"
  end
end
