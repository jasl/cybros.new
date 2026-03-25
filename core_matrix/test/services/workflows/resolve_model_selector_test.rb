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
    assert_equal "gpt-5.4", snapshot["resolved_model_ref"]
    assert_equal 1, snapshot["fallback_count"]
    assert_equal "role_fallback_after_reservation", snapshot["resolution_reason"]
  end

  test "role main fails when no real provider candidate is usable" do
    context = create_selector_context!(
      codex_credential_present: false,
      openai_credential_present: false,
      openrouter_credential_present: false,
      dev_entitlement_active: true,
      openrouter_entitlement_active: true
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
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

    assert_match(
      /no candidate available for role:main/,
      error.record.errors[:resolved_model_selection_snapshot].join(" ")
    )
  end

  test "role mock resolves the dev provider without affecting role main ordering" do
    context = create_selector_context!(
      codex_credential_present: false,
      openai_credential_present: false,
      openrouter_credential_present: false,
      dev_entitlement_active: true,
      openrouter_entitlement_active: false
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
      selector_source: "slot",
      selector: "role:mock"
    )

    assert_equal "role:mock", snapshot["normalized_selector"]
    assert_equal "mock", snapshot["resolved_role_name"]
    assert_equal "dev", snapshot["resolved_provider_handle"]
    assert_equal "mock-model", snapshot["resolved_model_ref"]
    assert_equal 0, snapshot["fallback_count"]
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

  test "explicit candidate selection fails immediately when the provider credential is missing" do
    context = create_selector_context!(
      openrouter_credential_present: false,
      openrouter_entitlement_active: true
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "slot",
        selector: "candidate:openrouter/openai-gpt-5.4"
      )
    end

    assert_match(/missing_credential/, error.record.errors[:resolved_model_selection_snapshot].join(" "))
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
    openrouter_entitlement_active: false,
    dev_entitlement_active: false,
    codex_entitlement_metadata: {},
    openai_entitlement_metadata: {},
    codex_credential_present: true,
    openai_credential_present: true,
    openrouter_credential_present: true
  )
    context = create_workspace_context!
    capability_snapshot = create_capability_snapshot!(agent_deployment: context[:agent_deployment])
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)

    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    create_provider_entitlement!(
      installation: context[:installation],
      provider_handle: "codex_subscription",
      active: codex_entitlement_active,
      metadata: codex_entitlement_metadata
    )
    create_provider_entitlement!(
      installation: context[:installation],
      provider_handle: "openai",
      active: openai_entitlement_active,
      metadata: openai_entitlement_metadata
    )
    create_provider_entitlement!(
      installation: context[:installation],
      provider_handle: "openrouter",
      active: openrouter_entitlement_active
    )
    create_provider_entitlement!(
      installation: context[:installation],
      provider_handle: "dev",
      active: dev_entitlement_active
    )

    create_provider_credential!(installation: context[:installation], provider_handle: "codex_subscription", credential_kind: "oauth_codex") if codex_credential_present
    create_provider_credential!(installation: context[:installation], provider_handle: "openai", credential_kind: "api_key") if openai_credential_present
    create_provider_credential!(installation: context[:installation], provider_handle: "openrouter", credential_kind: "api_key") if openrouter_credential_present

    {
      conversation: conversation,
      capability_snapshot: capability_snapshot,
    }.merge(context)
  end

  def create_provider_entitlement!(installation:, provider_handle:, active:, metadata: {})
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: provider_handle,
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: active,
      metadata: metadata
    )
  end

  def create_provider_credential!(installation:, provider_handle:, credential_kind:)
    ProviderCredential.create!(
      installation: installation,
      provider_handle: provider_handle,
      credential_kind: credential_kind,
      secret: "secret-#{provider_handle}",
      last_rotated_at: Time.current,
      metadata: {}
    )
  end
end
