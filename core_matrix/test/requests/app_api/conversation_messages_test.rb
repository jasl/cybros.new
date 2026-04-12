require "test_helper"

class AppApiConversationMessagesTest < ActionDispatch::IntegrationTest
  test "appends a user message through the app api" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_no_difference(["Workspace.count", "Conversation.count"]) do
      assert_difference(["Turn.count", "Message.count"], +1) do
        post "/app_api/conversations/#{conversation.public_id}/messages",
          params: {
            content: "Follow up",
          },
          headers: app_api_headers(session.plaintext_token),
          as: :json
      end
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "conversation_message_create", response_body.fetch("method_id")
    assert_equal conversation.public_id, response_body.fetch("conversation_id")
    assert_equal "Follow up", response_body.dig("message", "content")
  end
end
