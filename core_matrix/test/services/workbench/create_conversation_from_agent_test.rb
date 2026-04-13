require "test_helper"

module Workbench
end

class Workbench::CreateConversationFromAgentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enables the agent materializes the default workspace and accepts the first user turn as pending bootstrap work" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: execution_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: execution_runtime
    )
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

    result = nil

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count", "Turn.count", "Message.count"], +1) do
        assert_no_difference("WorkflowRun.count") do
        result = Workbench::CreateConversationFromAgent.call(
          user: user,
          agent: agent,
          content: "Help me start",
          selector: "candidate:codex_subscription/gpt-5.3-codex"
        )
        end
      end
    end

    assert_equal user, result.workspace.user
    assert_equal agent, result.conversation.agent
    assert result.workspace.is_default?
    assert_equal "Help me start", result.message.content
    assert_equal result.conversation, result.turn.conversation
    assert_equal "pending", result.turn.workflow_bootstrap_state
    assert_equal "candidate:codex_subscription/gpt-5.3-codex", result.turn.workflow_bootstrap_payload.fetch("selector")
    refute_respond_to result, :workflow_run
  end

  test "allows overriding the execution runtime for the first turn" do
    installation = create_installation!
    user = create_user!(installation: installation)
    default_runtime = create_execution_runtime!(installation: installation)
    override_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: override_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: default_runtime
    )
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

    result = Workbench::CreateConversationFromAgent.call(
      user: user,
      agent: agent,
      content: "Use the other runtime",
      selector: "candidate:codex_subscription/gpt-5.3-codex",
      execution_runtime: override_runtime
    )

    assert_equal override_runtime, result.turn.execution_runtime
    assert_equal default_runtime, result.workspace.default_execution_runtime
    assert_equal "pending", result.turn.workflow_bootstrap_state
  end
end
