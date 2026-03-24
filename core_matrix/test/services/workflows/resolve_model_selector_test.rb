require "test_helper"

class Workflows::ResolveModelSelectorTest < ActiveSupport::TestCase
  test "normalizes conversation auto selection to role main and resolves the first available candidate" do
    context = create_selector_context!
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "conversation", snapshot["selector_source"]
    assert_equal "role:main", snapshot["normalized_selector"]
    assert_equal "main", snapshot["resolved_role_name"]
    assert_equal "codex_subscription", snapshot["resolved_provider_handle"]
    assert_equal "gpt-5.4", snapshot["resolved_model_ref"]
    assert_equal 0, snapshot["fallback_count"]
    assert_equal context[:capability_snapshot].id, snapshot["capability_snapshot_id"]
    assert_equal "shared_window", snapshot["entitlement_key"]
  end

  test "falls back only within the current role when reservation fails" do
    context = create_selector_context!(
      codex_entitlement_metadata: { "reservation_denied" => true }
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "role:main", snapshot["normalized_selector"]
    assert_equal "openai", snapshot["resolved_provider_handle"]
    assert_equal "gpt-5.3-chat-latest", snapshot["resolved_model_ref"]
    assert_equal 1, snapshot["fallback_count"]
    assert_equal "role_fallback_after_reservation", snapshot["resolution_reason"]
  end

  test "explicit candidate selection rejects fallback to unrelated models" do
    context = create_selector_context!(
      codex_entitlement_active: false
    )
    Conversations::UpdateOverride.call(
      conversation: context[:conversation],
      payload: {},
      schema_fingerprint: "schema-v1",
      selector_mode: "explicit_candidate",
      selector_provider_handle: "codex_subscription",
      selector_model_ref: "gpt-5.4"
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "conversation"
      )
    end
  end

  test "specialized role exhaustion does not fall back to main" do
    context = create_selector_context!(
      openai_entitlement_active: false
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "slot",
        selector: "role:planner"
      )
    end
  end

  test "requires an active capability snapshot to freeze resolution" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    ProviderEntitlement.create!(
      installation: context[:installation],
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
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
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "conversation"
      )
    end

    assert_includes error.record.errors[:resolved_model_selection_snapshot], "requires an active capability snapshot"
  end

  private

  def create_selector_context!(
    codex_entitlement_active: true,
    openai_entitlement_active: true,
    codex_entitlement_metadata: {},
    openai_entitlement_metadata: {}
  )
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
      active: codex_entitlement_active,
      metadata: codex_entitlement_metadata
    )
    ProviderEntitlement.create!(
      installation: context[:installation],
      provider_handle: "openai",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: openai_entitlement_active,
      metadata: openai_entitlement_metadata
    )

    {
      conversation: conversation,
      capability_snapshot: capability_snapshot,
    }.merge(context)
  end
end
