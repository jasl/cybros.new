require "test_helper"

class AgentApiCoverageContractTest < ActiveSupport::TestCase
  test "fenix control client covers the current core matrix agent_api surface" do
    client = Fenix::Runtime::ControlClient.new(
      base_url: "https://core-matrix.example.test",
      machine_credential: "secret"
    )

    expected_methods = %i[
      register!
      heartbeat!
      health
      capabilities_refresh
      capabilities_handshake!
      conversation_transcript_list
      conversation_variables_get
      conversation_variables_mget
      conversation_variables_exists
      conversation_variables_list_keys
      conversation_variables_resolve
      conversation_variables_set
      conversation_variables_delete
      conversation_variables_promote
      workspace_variables_list
      workspace_variables_get
      workspace_variables_mget
      workspace_variables_write
      request_human_interaction!
      create_tool_invocation!
      create_command_run!
      activate_command_run!
      create_process_run!
      poll
      report!
    ]

    expected_methods.each do |method_name|
      assert_respond_to client, method_name
    end
  end
end
