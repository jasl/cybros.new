require "test_helper"

class AppApiConversationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "creates a conversation from an explicit workspace agent as pending execution" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_no_difference(["Workspace.count", "WorkspaceAgent.count"]) do
        assert_difference(["Conversation.count", "Turn.count", "Message.count"], +1) do
          assert_no_difference("WorkflowRun.count") do
            post "/app_api/conversations",
              params: {
                workspace_agent_id: context[:workspace_agent].public_id,
                content: "Start from conversations endpoint",
                selector: "candidate:codex_subscription/gpt-5.3-codex",
              },
              headers: app_api_headers(session.plaintext_token),
              as: :json
          end
        end
      end
    end

    assert_response :created
    body = response.parsed_body
    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [body.dig("conversation", "conversation_id"), body.fetch("turn_id")], title_job[:args]
    assert_equal "conversation_create", body.fetch("method_id")
    assert_equal context[:agent].public_id, body.dig("conversation", "agent_id")
    assert_equal context[:workspace_agent].public_id, body.dig("conversation", "workspace_agent_id")
    assert_equal context[:execution_runtime].public_id, body.dig("conversation", "current_execution_runtime_id")
    assert_equal "ready", body.dig("conversation", "execution_continuity_state")
    assert body.dig("conversation", "current_execution_epoch_id").present?
    assert_equal context[:workspace_agent].public_id, body.dig("workspace", "workspace_agents", 0, "workspace_agent_id")
    assert_equal "pending", body.fetch("execution_status")
    assert body.fetch("accepted_at").present?
    assert_equal "Start from conversations endpoint.", body.fetch("request_summary")
  end

  test "requires workspace_agent_id and does not materialize a default workspace on first use" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])

    assert_no_difference(["Workspace.count", "WorkspaceAgent.count", "Conversation.count", "Turn.count", "Message.count", "WorkflowRun.count"]) do
      post "/app_api/conversations",
        params: {
          agent_id: context[:agent].public_id,
          content: "Help me start",
          selector: "candidate:codex_subscription/gpt-5.3-codex",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :unprocessable_entity
  end

  test "allows overriding the execution runtime for the first turn" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    override_runtime = create_execution_runtime!(installation: context[:installation])
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: override_runtime)

    assert_enqueued_with(job: Conversations::Metadata::BootstrapTitleJob) do
      assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
        post "/app_api/conversations",
          params: {
            workspace_agent_id: context[:workspace_agent].public_id,
            content: "Use the other runtime",
            selector: "candidate:codex_subscription/gpt-5.3-codex",
            execution_runtime_id: override_runtime.public_id,
          },
          headers: app_api_headers(session.plaintext_token),
          as: :json
      end
    end

    assert_response :created
    turn = Turn.find_by_public_id!(response.parsed_body.fetch("turn_id"))
    assert_equal override_runtime, turn.execution_runtime
    assert_equal context[:workspace_agent].public_id, turn.conversation.workspace_agent.public_id
    assert_equal I18n.t("conversations.defaults.untitled_title"), turn.conversation.reload.title
    assert turn.conversation.title_source_none?
  end

  test "uses the workspace agent default runtime for launchability checks" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    context[:agent].update!(default_execution_runtime: nil)

    post "/app_api/conversations",
      params: {
        workspace_agent_id: context[:workspace_agent].public_id,
        content: "Use the mounted runtime",
      },
      headers: app_api_headers(session.plaintext_token),
      as: :json

    assert_response :created
  end

  test "rejects first-turn runtime overrides that are not accessible to the current user" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    owner = create_user!(
      installation: context[:installation],
      identity: create_identity!,
      display_name: "Private Runtime Owner"
    )
    private_runtime = create_execution_runtime!(
      installation: context[:installation],
      visibility: "private",
      owner_user: owner
    )
    create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: private_runtime
    )

    assert_no_difference(["Conversation.count", "Turn.count", "Message.count", "WorkflowRun.count"]) do
      post "/app_api/conversations",
        params: {
          workspace_agent_id: context[:workspace_agent].public_id,
          content: "Use a private runtime",
          execution_runtime_id: private_runtime.public_id,
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :not_found
  end

  test "creates a conversation from the conversation-first endpoint within sixty SQL queries" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])

    assert_sql_query_count_at_most(60) do
      post "/app_api/conversations",
        params: {
          workspace_agent_id: context[:workspace_agent].public_id,
          content: "Start from conversations endpoint",
          selector: "candidate:codex_subscription/gpt-5.3-codex",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json

      assert_response :created
      assert_equal "pending", response.parsed_body.fetch("execution_status")
    end
  end

  test "rejects conversation creation when the workspace agent is no longer launchable" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    session = create_session!(user: context[:user])
    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    assert_no_difference(["Conversation.count", "Turn.count", "Message.count", "WorkflowRun.count"]) do
      post "/app_api/conversations",
        params: {
          workspace_agent_id: context[:workspace_agent].public_id,
          content: "Start a hidden conversation",
        },
        headers: app_api_headers(session.plaintext_token),
        as: :json
    end

    assert_response :not_found
  end
end
