require "test_helper"

class RuntimeCapabilities::ComposeForTurnTest < ActiveSupport::TestCase
  test "root turns do not expose a CoreMatrix-owned profile key" do
    registration = register_profile_aware_runtime!
    conversation = create_root_conversation_for!(registration)
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Profile test",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    composer = RuntimeCapabilities::ComposeForTurn.new(turn: turn)

    assert_equal turn.execution_runtime.public_id, composer.call.fetch("execution_runtime_id")
    assert_equal turn.execution_runtime_version.public_id, composer.call.fetch("execution_runtime_version_id")
    assert_equal turn.agent_definition_version.public_id, composer.call.fetch("agent_definition_version_id")
    assert_nil composer.current_profile_key
  end

  test "exposes the capability contract and child profile key for subagent turns" do
    registration = register_profile_aware_runtime!
    root_conversation = create_root_conversation_for!(registration)
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: root_conversation,
      depth: 0,
      profile_key: "researcher"
    ).fetch(:conversation)
    turn = Turns::StartAgentTurn.call(
      conversation: child,
      content: "Delegated input",
      sender_kind: "owner_agent",
      sender_conversation: root_conversation,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    composer = RuntimeCapabilities::ComposeForTurn.new(turn: turn)

    assert_equal "researcher", composer.current_profile_key
    assert_equal "main", composer.contract.default_canonical_config.dig("interactive", "profile")
  end

  test "subagent spawn schema stays profile-agnostic even when workspace settings change" do
    context = build_governed_tool_context!(
      workspace_agent_settings_payload: {
        "subagents" => {
          "enabled_profile_keys" => ["researcher"],
          "default_profile_key" => "researcher",
        },
      }
    )
    context.fetch(:conversation).workspace_agent.update!(
      settings_payload: {
        "subagents" => {
          "enabled_profile_keys" => ["critic"],
          "default_profile_key" => "critic",
        },
      }
    )

    entry = RuntimeCapabilities::ComposeForTurn.call(turn: context.fetch(:turn).reload).fetch("tool_catalog").find do |tool|
      tool.fetch("tool_name") == "subagent_spawn"
    end

    refute entry.dig("input_schema", "properties", "profile_key").key?("enum")
  end

  private

  def register_profile_aware_runtime!(profile_policy: default_profile_policy, default_canonical_config: profile_aware_default_canonical_config, execution_runtime_capability_payload: {}, tool_contract: default_tool_catalog("exec_command"))
    register_agent_runtime!(
      execution_runtime_capability_payload: execution_runtime_capability_payload,
      tool_contract: tool_contract,
      profile_policy: profile_policy,
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: default_canonical_config
    )
  end

  def create_root_conversation_for!(registration)
    workspace = create_workspace!(
      installation: registration[:installation],
      user: registration[:actor],
      default_execution_runtime: registration[:execution_runtime],
      agent: registration[:agent]
    )

    Conversations::CreateRoot.call(
      workspace: workspace,
    )
  end

  def create_subagent_conversation_chain!(registration:, parent_conversation:, depth:, profile_key:)
    previous_conversation = parent_conversation
    previous_session = nil

    (depth + 1).times do |index|
      conversation = create_conversation_record!(
        installation: registration[:installation],
        workspace: parent_conversation.workspace,
        parent_conversation: previous_conversation,
        kind: "fork",
        execution_runtime: registration[:execution_runtime],
        agent_definition_version: registration[:agent_definition_version],
        entry_policy_payload: agent_internal_entry_policy_payload
      )
      session = SubagentConnection.create!(
        installation: registration[:installation],
        conversation: conversation,
        user: conversation.user,
        workspace: conversation.workspace,
        agent: conversation.agent,
        owner_conversation: previous_conversation,
        parent_subagent_connection: previous_session,
        scope: "conversation",
        profile_key: profile_key,
        depth: index
      )

      previous_conversation = conversation
      previous_session = session
    end

    {
      conversation: previous_conversation,
      subagent_connection: previous_session,
    }
  end
end
