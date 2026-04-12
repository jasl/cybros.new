require "test_helper"

class Workbench::SendMessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "appends a new user turn to an existing conversation without creating a workspace or conversation" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    result = nil

    assert_no_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count"]) do
      assert_enqueued_with(job: Workflows::ExecuteNodeJob) do
        assert_difference(["Turn.count", "Message.count", "WorkflowRun.count"], +1) do
          result = Workbench::SendMessage.call(
            conversation: conversation,
            content: "Follow up"
          )
        end
      end
    end

    assert_equal conversation, result.conversation
    assert_equal "Follow up", result.message.content
    assert_equal result.turn, result.message.turn
    assert_equal result.turn, result.workflow_run.turn
  end

  test "allows overriding the execution runtime for a follow-up turn" do
    installation = create_installation!
    user = create_user!(installation: installation)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: override_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: default_runtime)
    create_agent_connection!(installation: installation, agent: agent)
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "oauth-codex-access-token",
      refresh_token: "oauth-codex-refresh-token",
      expires_at: 2.hours.from_now,
      last_rotated_at: Time.current,
      metadata: {}
    )
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: default_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace, agent: agent)

    result = Workbench::SendMessage.call(
      conversation: conversation,
      content: "Follow up",
      selector: "candidate:codex_subscription/gpt-5.3-codex",
      execution_runtime: override_runtime
    )

    assert_equal override_runtime, result.turn.execution_runtime
  end
end
