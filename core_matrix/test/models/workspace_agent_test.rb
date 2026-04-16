require "test_helper"

class WorkspaceAgentTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent]
    )

    assert workspace_agent.public_id.present?
    assert_equal workspace_agent, WorkspaceAgent.find_by_public_id!(workspace_agent.public_id)
  end

  test "belongs to workspace and agent with an optional default execution runtime" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      default_execution_runtime: context[:execution_runtime]
    )

    assert_equal :belongs_to, WorkspaceAgent.reflect_on_association(:workspace)&.macro
    assert_equal :belongs_to, WorkspaceAgent.reflect_on_association(:agent)&.macro
    assert_equal :belongs_to, WorkspaceAgent.reflect_on_association(:default_execution_runtime)&.macro
    assert workspace_agent.valid?, workspace_agent.errors.full_messages.to_sentence
  end

  test "allows only one active mount per workspace and agent" do
    context = workspace_agent_context
    WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )

    duplicate = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:workspace_id].present? || duplicate.errors[:agent_id].present? || duplicate.errors[:base].present?
  end

  test "normalizes disabled capabilities from capability_policy_payload" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      capability_policy_payload: {
        "disabled_capabilities" => %i[control side_chat control unknown],
      }
    )

    assert_equal %w[control side_chat], workspace_agent.disabled_capabilities
  end

  test "normalizes blank global instructions to nil" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      global_instructions: " \n\t "
    )

    assert_nil workspace_agent.global_instructions
  end

  test "normalizes structured settings payload" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      settings_payload: {
        "interactive" => {
          "profile_key" => "friendly",
          "model_selector" => "role:main",
        },
        "subagents" => {
          "default_profile_key" => "researcher",
          "enabled_profile_keys" => ["researcher", "", "researcher"],
          "delegation_mode" => "prefer",
          "max_concurrent" => "3",
          "max_depth" => "2",
          "allow_nested" => false,
          "default_model_selector" => "role:main",
          "profile_overrides" => {
            "researcher" => {
              "model_selector" => "role:researcher",
            },
          },
        },
      }
    )

    assert_equal(
      {
        "interactive" => {
          "profile_key" => "friendly",
          "model_selector" => "role:main",
        },
        "subagents" => {
          "default_profile_key" => "researcher",
          "enabled_profile_keys" => ["researcher"],
          "delegation_mode" => "prefer",
          "max_concurrent" => 3,
          "max_depth" => 2,
          "allow_nested" => false,
          "default_model_selector" => "role:main",
          "profile_overrides" => {
            "researcher" => {
              "model_selector" => "role:researcher",
            },
          },
        },
      },
      workspace_agent.settings_payload
    )
  end

  test "rejects unsupported capability policy payload keys" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      capability_policy_payload: {
        "disabled_capabilities" => ["control"],
        "unexpected" => true,
      }
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:capability_policy_payload], "must only contain supported keys"
  end

  test "rejects unsupported settings payload keys" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      settings_payload: {
        "interactive" => {
          "profile_key" => "main",
        },
        "unexpected" => true,
      }
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:settings_payload], "must only contain supported keys"
  end

  test "requires the default subagent profile to remain enabled when the enabled list is present" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      settings_payload: {
        "subagents" => {
          "default_profile_key" => "researcher",
          "enabled_profile_keys" => [],
        },
      }
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:settings_payload], "default_subagent_profile_key must be included in enabled_subagent_profile_keys"
  end

  test "normalizes interactive profiles out of the enabled specialist list" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      settings_payload: {
        "interactive" => {
          "profile_key" => "main",
        },
        "subagents" => {
          "enabled_profile_keys" => %w[main researcher],
        },
      }
    )

    assert_equal ["researcher"], workspace_agent.settings_payload.dig("subagents", "enabled_profile_keys")
  end

  test "rejects invalid numeric subagent limits instead of dropping them" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.new(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      settings_payload: {
        "subagents" => {
          "max_concurrent" => "abc",
        },
      }
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:settings_payload], "subagents.max_concurrent must be a positive integer"
  end

  test "becomes immutable after revocation" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    workspace_agent.default_execution_runtime = context[:execution_runtime]

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:base], "is immutable once revoked or retired"
  end

  test "rejects policy or runtime changes while transitioning to a terminal state" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )

    workspace_agent.assign_attributes(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked",
      default_execution_runtime: context[:execution_runtime]
    )

    assert_not workspace_agent.valid?
    assert_includes workspace_agent.errors[:base], "cannot change policy or runtime while transitioning to a terminal state"
  end

  test "revoking a mount disables ingress bindings and channel connectors" do
    context = workspace_agent_context
    workspace_agent = WorkspaceAgent.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      agent: context[:agent],
      lifecycle_state: "active"
    )
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: workspace_agent,
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )

    workspace_agent.update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "owner_revoked"
    )

    assert_equal "disabled", ingress_binding.reload.lifecycle_state
    assert_equal "disabled", channel_connector.reload.lifecycle_state
  end

  private

  def workspace_agent_context
    installation = create_installation!
    user = create_user!(installation: installation)
    workspace = Workspace.create!(
      installation: installation,
      user: user,
      name: "Workspace Agent Context",
      privacy: "private"
    )
    execution_runtime = create_execution_runtime!(installation: installation)
    agent = create_agent!(installation: installation)
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      profile_policy: default_profile_policy,
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )
    create_agent_connection!(
      installation: installation,
      agent: agent,
      agent_definition_version: agent_definition_version
    )

    {
      installation: installation,
      workspace: workspace,
      agent: agent,
      execution_runtime: execution_runtime,
    }
  end
end
