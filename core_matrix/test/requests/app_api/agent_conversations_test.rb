require "test_helper"

class AppApiAgentConversationsTest < ActionDispatch::IntegrationTest
  test "creates a conversation from an agent and materializes the default workspace on first use" do
    installation = create_installation!
    user = create_user!(installation: installation)
    session = create_session!(user: user)
    execution_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: execution_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: execution_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)

    assert_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count", "Turn.count", "Message.count"], +1) do
      post "/app_api/agents/#{agent.public_id}/conversations",
        params: {
          content: "Help me start",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "agent_conversation_create", response_body.fetch("method_id")
    assert_equal agent.public_id, response_body.fetch("agent_id")
    assert_equal "Help me start", response_body.dig("message", "content")
    assert_equal true, response_body.dig("workspace", "is_default")
  end
end
