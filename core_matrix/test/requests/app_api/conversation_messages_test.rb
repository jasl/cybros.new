require "test_helper"

class AppApiConversationMessagesTest < ActionDispatch::IntegrationTest
  test "appends a user message through the app api" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_no_difference(["Workspace.count", "Conversation.count"]) do
      assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
        assert_difference(["Turn.count", "Message.count", "WorkflowRun.count"], +1) do
          post "/app_api/conversations/#{conversation.public_id}/messages",
            params: {
              content: "Follow up",
            },
            headers: app_api_headers(session.plaintext_token),
            as: :json
        end
      end
    end

    assert_response :created

    response_body = response.parsed_body
    assert_equal "conversation_message_create", response_body.fetch("method_id")
    assert_equal conversation.public_id, response_body.fetch("conversation_id")
    assert_equal "Follow up", response_body.dig("message", "content")
  end

  test "rejects execution runtime handoff on follow-up messages" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])

    assert_no_difference("Turn.count") do
      post "/app_api/conversations/#{conversation.public_id}/messages",
        params: {
          content: "Follow up",
          execution_runtime_id: context[:execution_runtime].public_id,
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "conversation_runtime_handoff_not_implemented", response.parsed_body.fetch("method_id")
    assert_equal "conversation runtime handoff is not implemented yet", response.parsed_body.fetch("error")
  end
end
