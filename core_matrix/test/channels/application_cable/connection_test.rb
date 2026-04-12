require "test_helper"
require "action_cable/connection/test_case"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    tests ApplicationCable::Connection

    test "connects with an agent connection and exposes the default execution runtime" do
      context = create_workspace_context!
      agent_connection_credential = "cable-connection-credential-#{next_test_sequence}"
      context[:agent_connection].update!(
        connection_credential_digest: AgentConnection.digest_connection_credential(agent_connection_credential)
      )

      connect params: { token: agent_connection_credential }

      assert_equal context[:agent_definition_version], connection.current_agent_definition_version
      assert_equal context[:execution_runtime], connection.current_execution_runtime
      assert_nil connection.current_publication
    end

    test "connects with an execution runtime connection" do
      context = create_workspace_context!
      execution_runtime_credential = "cable-execution-runtime-credential-#{next_test_sequence}"
      context[:execution_runtime_connection].update!(
        connection_credential_digest: ExecutionRuntimeConnection.digest_connection_credential(execution_runtime_credential)
      )

      connect params: { token: execution_runtime_credential }

      assert_nil connection.current_agent_definition_version
      assert_equal context[:execution_runtime_connection], connection.current_execution_runtime_connection
      assert_equal context[:execution_runtime], connection.current_execution_runtime
      assert_nil connection.current_publication
    end

    test "connects with a verified external publication token" do
      context = create_workspace_context!
      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version]
      )
      publication = Publications::PublishLive.call(
        conversation: conversation,
        actor: context[:user],
        visibility_mode: "external_public"
      )

      connect params: { publication_token: publication.plaintext_access_token }

      assert_nil connection.current_agent_definition_version
      assert_nil connection.current_execution_runtime
      assert_equal publication, connection.current_publication
    end

    test "rejects connection without a verified agent definition version or publication token" do
      assert_reject_connection { connect }
    end
  end
end
