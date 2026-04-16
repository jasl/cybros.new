require "test_helper"

class Workflows::ResolveModelSelectorTest < ActiveSupport::TestCase
  test "normalizes conversation auto selection to role main and resolves the first available candidate" do
    context = create_selector_context!
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
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
    assert_equal context[:agent_definition_version].public_id, snapshot["agent_definition_version_id"]
    assert_equal "shared_window", snapshot["entitlement_key"]
  end

  test "falls back only within the current role when reservation fails" do
    context = create_selector_context!(
      codex_entitlement_metadata: { "reservation_denied" => true }
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
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

  test "explicit candidate selection fails immediately when the model is disabled" do
    context = create_selector_context!(
      openrouter_entitlement_active: true
    )
    disabled_catalog_definition = test_provider_catalog_definition.deep_dup
    disabled_catalog_definition[:providers][:openrouter][:models]["openai-gpt-5.4"][:enabled] = false
    disabled_catalog = build_test_provider_catalog_from(disabled_catalog_definition)

    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    with_stubbed_provider_catalog(disabled_catalog) do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Workflows::ResolveModelSelector.call(
          turn: turn,
          selector_source: "slot",
          selector: "candidate:openrouter/openai-gpt-5.4"
        )
      end

      assert_match(/model_disabled/, error.record.errors[:resolved_model_selection_snapshot].join(" "))
    end
  end

  test "role main skips disabled models and resolves the next candidate" do
    context = create_selector_context!
    disabled_catalog_definition = test_provider_catalog_definition.deep_dup
    disabled_catalog_definition[:providers][:codex_subscription][:models]["gpt-5.4"][:enabled] = false
    disabled_catalog = build_test_provider_catalog_from(disabled_catalog_definition)

    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    with_stubbed_provider_catalog(disabled_catalog) do
      snapshot = Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "conversation"
      )

      assert_equal "role:main", snapshot["normalized_selector"]
      assert_equal "openai", snapshot["resolved_provider_handle"]
      assert_equal "gpt-5.4", snapshot["resolved_model_ref"]
      assert_equal 1, snapshot["fallback_count"]
      assert_equal "role_fallback_after_filter", snapshot["resolution_reason"]
    end
  end

  test "specialized role exhaustion does not fall back to main" do
    context = create_selector_context!(
      openai_entitlement_active: false
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
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

  test "workspace agent interactive profile override prefers a matching role without mutating agent config state" do
    context = create_selector_context!
    planner_version = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      profile_policy: default_profile_policy.merge(
        "planner" => {
          "label" => "Planner",
          "description" => "Planning profile",
        }
      ),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, planner_version, turn: nil)
    context[:workspace_agent].update!(
      settings_payload: {
        "interactive_profile_key" => "planner",
      }
    )

    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "role:planner", snapshot["normalized_selector"]
    assert_equal "planner", snapshot["resolved_role_name"]
    assert_equal "openai", snapshot["resolved_provider_handle"]
    assert_equal "gpt-5.4", snapshot["resolved_model_ref"]
    assert_equal "main", context[:agent].agent_config_state.effective_payload.dig("interactive", "profile")
  end

  test "workspace agent interactive profile override does not shadow an explicit selector" do
    context = create_selector_context!
    planner_version = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      profile_policy: default_profile_policy.merge(
        "planner" => {
          "label" => "Planner",
          "description" => "Planning profile",
        }
      ),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, planner_version, turn: nil)
    context[:workspace_agent].update!(
      settings_payload: {
        "interactive_profile_key" => "researcher",
      }
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "slot",
      selector: "role:planner"
    )

    assert_equal "role:planner", snapshot["normalized_selector"]
    assert_equal "planner", snapshot["resolved_role_name"]
  end

  test "workspace agent interactive profile override falls back cleanly when the profile has no provider role" do
    context = create_selector_context!
    friendly_version = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      profile_policy: default_profile_policy.merge(
        "friendly" => {
          "label" => "Friendly",
          "description" => "Interactive profile with local prompt-only routing",
        }
      ),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, friendly_version, turn: nil)
    context[:workspace_agent].update!(
      settings_payload: {
        "interactive_profile_key" => "friendly",
      }
    )
    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "role:main", snapshot["normalized_selector"]
    assert_equal "main", snapshot["resolved_role_name"]
  end

  test "workspace agent interactive model selector override is tried before the profile selector" do
    context = create_selector_context!
    planner_version = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      profile_policy: default_profile_policy.merge(
        "planner" => {
          "label" => "Planner",
          "description" => "Planning profile",
        }
      ),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, planner_version, turn: nil)
    context[:workspace_agent].update!(
      settings_payload: {
        "interactive" => {
          "profile_key" => "researcher",
          "model_selector" => "role:planner",
        },
      }
    )

    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "role:planner", snapshot["normalized_selector"]
    assert_equal "planner", snapshot["resolved_role_name"]
  end

  test "workspace agent interactive model selector override falls back to the profile selector when unavailable" do
    context = create_selector_context!
    planner_version = create_compatible_agent_definition_version!(
      agent_definition_version: context[:agent_definition_version],
      profile_policy: default_profile_policy.merge(
        "planner" => {
          "label" => "Planner",
          "description" => "Planning profile",
        }
      ),
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    adopt_agent_definition_version!(context, planner_version, turn: nil)
    context[:workspace_agent].update!(
      settings_payload: {
        "interactive" => {
          "profile_key" => "planner",
          "model_selector" => "role:friendly",
        },
      }
    )

    turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Selector input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "role:planner", snapshot["normalized_selector"]
    assert_equal "planner", snapshot["resolved_role_name"]
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
    capability_snapshot = create_compatible_agent_definition_version!(agent_definition_version: context[:agent_definition_version])
    adopt_agent_definition_version!(context, capability_snapshot, turn: nil)

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )

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
      agent_definition_version: context[:agent_definition_version],
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
    attributes = {
      installation: installation,
      provider_handle: provider_handle,
      credential_kind: credential_kind,
      last_rotated_at: Time.current,
      metadata: {},
    }

    if credential_kind == "oauth_codex"
      attributes.merge!(
        access_token: "access-#{provider_handle}",
        refresh_token: "refresh-#{provider_handle}",
        expires_at: 2.hours.from_now,
      )
    else
      attributes[:secret] = "secret-#{provider_handle}"
    end

    ProviderCredential.create!(attributes)
  end
end
