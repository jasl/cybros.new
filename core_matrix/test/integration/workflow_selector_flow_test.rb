require "test_helper"

class WorkflowSelectorFlowTest < ActionDispatch::IntegrationTest
  test "create for turn freezes the resolved model snapshot after role-local fallback" do
    context = create_workspace_context!
    capability_snapshot = create_capability_snapshot!(agent_deployment: context[:agent_deployment])
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    ProviderEntitlement.create!(
      installation: context[:installation],
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: { "reservation_denied" => true }
    )
    ProviderEntitlement.create!(
      installation: context[:installation],
      provider_handle: "openai",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: context[:installation],
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      secret: "secret-codex",
      last_rotated_at: Time.current,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: context[:installation],
      provider_handle: "openai",
      credential_kind: "api_key",
      secret: "secret-openai",
      last_rotated_at: Time.current,
      metadata: {}
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    assert_equal "conversation", turn.reload.resolved_model_selection_snapshot["selector_source"]
    assert_equal "role:main", turn.resolved_model_selection_snapshot["normalized_selector"]
    assert_equal "openai", turn.resolved_model_selection_snapshot["resolved_provider_handle"]
    assert_equal "gpt-5.4", turn.resolved_model_selection_snapshot["resolved_model_ref"]
    assert_equal 1, turn.resolved_model_selection_snapshot["fallback_count"]
    assert_equal "openai", workflow_run.resolved_provider_handle
    assert_equal "gpt-5.4", workflow_run.resolved_model_ref
  end
end
