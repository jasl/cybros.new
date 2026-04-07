require "test_helper"
require "action_cable/connection/test_case"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    tests ApplicationCable::Connection

    test "connects with an agent session and exposes the default executor program" do
      context = create_workspace_context!
      machine_credential = "cable-session-credential-#{next_test_sequence}"
      context[:agent_session].update!(
        session_credential_digest: AgentSession.digest_session_credential(machine_credential)
      )

      connect params: { token: machine_credential }

      assert_equal context[:agent_program_version], connection.current_deployment
      assert_equal context[:execution_runtime], connection.current_execution_runtime
      assert_nil connection.current_publication
    end

    test "connects with a verified external publication token" do
      context = create_workspace_context!
      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
        execution_runtime: context[:execution_runtime],
        agent_program_version: context[:agent_program_version]
      )
      publication = Publications::PublishLive.call(
        conversation: conversation,
        actor: context[:user],
        visibility_mode: "external_public"
      )

      connect params: { publication_token: publication.plaintext_access_token }

      assert_nil connection.current_deployment
      assert_nil connection.current_execution_runtime
      assert_equal publication, connection.current_publication
    end

    test "rejects connection without a verified deployment or publication token" do
      assert_reject_connection { connect }
    end
  end
end
