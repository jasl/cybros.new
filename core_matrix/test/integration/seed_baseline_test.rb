require "test_helper"

class SeedBaselineTest < ActiveSupport::TestCase
  test "seeds validate the catalog reconcile the bundled runtime and create an idempotent dev baseline without inventing user data" do
    installation = create_installation!
    initial_installation_count = Installation.count
    initial_identity_count = Identity.count
    initial_user_count = User.count
    initial_workspace_agent_count = WorkspaceAgent.count
    initial_workspace_count = Workspace.count
    initial_agent_count = Agent.count
    initial_environment_count = ExecutionRuntime.count
    initial_agent_definition_version_count = AgentDefinitionVersion.count

    run_seed_script!(
      installation: installation,
      bundled_agent_configuration: bundled_agent_configuration(enabled: true),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => nil }
    )
    run_seed_script!(
      installation: installation,
      bundled_agent_configuration: bundled_agent_configuration(enabled: true),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => nil }
    )

    assert_equal initial_installation_count, Installation.count
    assert_equal installation, Installation.first
    assert_equal initial_agent_count + 1, Agent.count
    assert_equal initial_environment_count + 1, ExecutionRuntime.count
    assert_equal initial_agent_definition_version_count + 1, AgentDefinitionVersion.count
    assert_equal initial_identity_count, Identity.count
    assert_equal initial_user_count, User.count
    assert_equal initial_workspace_agent_count, WorkspaceAgent.count
    assert_equal initial_workspace_count, Workspace.count
    assert_equal 1, ProviderPolicy.where(installation: installation, provider_handle: "dev").count
    assert_equal 1, ProviderEntitlement.where(installation: installation, provider_handle: "dev").count
    bundled_agent = Agent.find_by!(installation: installation, key: bundled_agent_configuration(enabled: true).fetch(:agent_key))
    bundled_runtime = ExecutionRuntime.find_by!(installation: installation, published_execution_runtime_version_id: bundled_agent.default_execution_runtime.published_execution_runtime_version_id)
    assert_equal bundled_agent.published_agent_definition_version, bundled_agent.current_agent_definition_version
    assert_equal bundled_runtime.published_execution_runtime_version, bundled_runtime.current_execution_runtime_version
    assert ProviderPolicy.find_by!(installation: installation, provider_handle: "dev").enabled
    assert ProviderEntitlement.find_by!(installation: installation, provider_handle: "dev").active?
    assert_equal 1, AuditLog.where(installation: installation, action: "provider_policy.upserted").count
    assert_equal 1, AuditLog.where(installation: installation, action: "provider_entitlement.upserted").count
  end

  test "seeds import openrouter credentials idempotently when the environment variable is present" do
    installation = create_installation!

    run_seed_script!(
      installation: installation,
      bundled_agent_configuration: bundled_agent_configuration(enabled: false),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => "or-live-123" }
    )
    run_seed_script!(
      installation: installation,
      bundled_agent_configuration: bundled_agent_configuration(enabled: false),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => "or-live-123" }
    )

    credential = ProviderCredential.find_by!(installation: installation, provider_handle: "openrouter", credential_kind: "api_key")

    assert_equal "or-live-123", credential.secret
    assert_equal 1, ProviderCredential.where(installation: installation, provider_handle: "openrouter").count
    assert_equal 1, AuditLog.where(installation: installation, action: "provider_credential.upserted").count
    assert ProviderPolicy.find_by!(installation: installation, provider_handle: "openrouter").enabled
    assert ProviderEntitlement.find_by!(installation: installation, provider_handle: "openrouter").active?
  end

  test "seeds keep role mock usable when only the dev baseline is present" do
    context = create_workspace_context!
    capability_snapshot = create_compatible_agent_definition_version!(agent_definition_version: context[:agent_definition_version])
    adopt_agent_definition_version!(context, capability_snapshot, turn: nil)

    run_seed_script!(
      installation: context[:installation],
      bundled_agent_configuration: bundled_agent_configuration(enabled: false),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => nil }
    )

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Seed selector",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "slot",
      selector: "role:mock"
    )

    assert_equal "auto", conversation.reload.interactive_selector_mode
    assert_equal "role:mock", snapshot["normalized_selector"]
    assert_equal "dev", snapshot["resolved_provider_handle"]
    assert_equal "mock-model", snapshot["resolved_model_ref"]
  end

  test "auto selector fails without a usable real provider even when the dev baseline is present" do
    context = create_workspace_context!
    capability_snapshot = create_compatible_agent_definition_version!(agent_definition_version: context[:agent_definition_version])
    adopt_agent_definition_version!(context, capability_snapshot, turn: nil)

    run_seed_script!(
      installation: context[:installation],
      bundled_agent_configuration: bundled_agent_configuration(enabled: false),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => nil }
    )

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Seed selector",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ResolveModelSelector.call(
        turn: turn,
        selector_source: "conversation"
      )
    end

    assert_equal "auto", conversation.reload.interactive_selector_mode
    assert_match(/no candidate available for role:main/, error.record.errors[:resolved_model_selection_snapshot].join(" "))
  end

  test "seeded real provider credentials plus seeded governance keep role main usable without changing auto selector mode" do
    context = create_workspace_context!
    capability_snapshot = create_compatible_agent_definition_version!(agent_definition_version: context[:agent_definition_version])
    adopt_agent_definition_version!(context, capability_snapshot, turn: nil)

    run_seed_script!(
      installation: context[:installation],
      bundled_agent_configuration: bundled_agent_configuration(enabled: false),
      env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => "or-live-123" }
    )

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Seed selector",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    snapshot = Workflows::ResolveModelSelector.call(
      turn: turn,
      selector_source: "conversation"
    )

    assert_equal "auto", conversation.reload.interactive_selector_mode
    assert_equal "role:main", snapshot["normalized_selector"]
    assert_equal "openrouter", snapshot["resolved_provider_handle"]
    assert_equal "openai-gpt-5.4", snapshot["resolved_model_ref"]
  end

  test "seed runner rejects ambiguous installation sets before loading db seeds" do
    installation = create_installation!
    timestamp = Time.current

    Installation.insert_all!([
      {
        name: "Secondary installation",
        bootstrap_state: "bootstrapped",
        global_settings: {},
        created_at: timestamp,
        updated_at: timestamp,
      },
    ])

    error = assert_raises(ArgumentError) do
      run_seed_script!(
        installation: installation,
        bundled_agent_configuration: bundled_agent_configuration(enabled: false),
        env: { "OPENAI_API_KEY" => nil, "OPENROUTER_API_KEY" => nil }
      )
    end

    assert_match(/expected exactly one installation/i, error.message)
  end
end
