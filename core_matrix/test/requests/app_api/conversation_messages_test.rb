require "test_helper"

class AppApiConversationMessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "appends a user message through the app api as pending execution" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_no_difference(["Workspace.count", "Conversation.count"]) do
      assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
        assert_difference(["Turn.count", "Message.count"], +1) do
          assert_no_difference("WorkflowRun.count") do
          post "/app_api/conversations/#{conversation.public_id}/messages",
            params: {
              content: "Follow up",
            },
            headers: app_api_headers(session.plaintext_token),
            as: :json
          end
        end
      end
    end

    assert_response :created

    response_body = response.parsed_body
    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [conversation.public_id, response_body.fetch("turn_id")], title_job[:args]
    assert_equal "conversation_message_create", response_body.fetch("method_id")
    assert_equal conversation.public_id, response_body.fetch("conversation_id")
    assert_equal "Follow up", response_body.dig("message", "content")
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.reload.title
    assert conversation.title_source_none?
    assert_equal "pending", response_body.fetch("execution_status")
    assert response_body.fetch("accepted_at").present?
    assert_equal "Follow up.", response_body.fetch("request_summary")
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
    initialize_current_execution_epoch!(conversation)
    ConversationExecutionEpochs::RetargetCurrent.call(
      conversation: conversation,
      execution_runtime: alternate_runtime
    )

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      post "/app_api/conversations/#{conversation.public_id}/messages",
        params: {
          content: "Use conversation current runtime",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :created
    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [conversation.public_id, response.parsed_body.fetch("turn_id")], title_job[:args]
    turn = Turn.find_by_public_id!(response.parsed_body.fetch("turn_id"))
    assert_equal alternate_runtime, turn.execution_runtime
    assert_equal conversation.current_execution_epoch, turn.execution_epoch
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.reload.title
    assert conversation.title_source_none?
  end

  test "appends a user message through the app api within fifty SQL queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_sql_query_count_at_most(50) do
      post "/app_api/conversations/#{conversation.public_id}/messages",
        params: {
          content: "Follow up",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json

      assert_response :created
      assert_equal "pending", response.parsed_body.fetch("execution_status")
    end
  end
end
