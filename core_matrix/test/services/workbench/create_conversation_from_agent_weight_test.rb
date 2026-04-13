require "test_helper"

class Workbench::CreateConversationFromAgentWeightTest < ActiveSupport::TestCase
  test "creates the first pending turn within fifty-two SQL queries" do
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

    assert_sql_query_count_at_most(52) do
      result = Workbench::CreateConversationFromAgent.call(
        user: user,
        agent: agent,
        content: "Help me start",
        selector: "candidate:codex_subscription/gpt-5.3-codex"
      )

      assert_equal "pending", result.turn.workflow_bootstrap_state
    end
  end
end
