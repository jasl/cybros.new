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

  test "uses the conversation current execution runtime instead of deriving from prior turns" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    alternate_runtime = create_execution_runtime!(installation: context[:installation])
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: alternate_runtime)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    initialize_current_execution_epoch!(conversation).update!(execution_runtime: alternate_runtime)
    conversation.update!(current_execution_runtime: alternate_runtime)

    post "/app_api/conversations/#{conversation.public_id}/messages",
      params: {
        content: "Use conversation current runtime",
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :created
    turn = Turn.find_by_public_id!(response.parsed_body.fetch("turn_id"))
    assert_equal alternate_runtime, turn.execution_runtime
    assert_equal conversation.current_execution_epoch, turn.execution_epoch
  end

  test "appends a user message through the app api within eighty-four SQL queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_sql_query_count_at_most(84) do
      post "/app_api/conversations/#{conversation.public_id}/messages",
        params: {
          content: "Follow up",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json

      assert_response :created
    end
  end
end
