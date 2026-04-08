require "test_helper"

class RuntimeCapabilities::ComposeForTurnTest < ActiveSupport::TestCase
  test "exposes the current profile key for root turns" do
    registration = register_profile_aware_runtime!
    conversation = create_root_conversation_for!(registration)
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Profile test",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    composer = RuntimeCapabilities::ComposeForTurn.new(turn: turn)

    assert_equal "main", composer.current_profile_key
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
    assert_equal "main", composer.contract.default_config_snapshot.dig("interactive", "profile")
  end

  private

  def register_profile_aware_runtime!
    register_agent_runtime!(
      tool_catalog: default_tool_catalog("exec_command"),
      profile_catalog: default_profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )
  end

  def create_root_conversation_for!(registration)
    workspace = create_workspace!(
      installation: registration[:installation],
      user: registration[:actor],
      user_program_binding: create_user_program_binding!(
        installation: registration[:installation],
        user: registration[:actor],
        agent_program: registration[:agent_program]
      )
    )

    Conversations::CreateRoot.call(
      workspace: workspace,
      executor_program: registration[:executor_program],
      agent_program_version: registration[:deployment]
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
        executor_program: registration[:executor_program],
        agent_program_version: registration[:deployment],
        addressability: "agent_addressable"
      )
      session = SubagentSession.create!(
        installation: registration[:installation],
        conversation: conversation,
        owner_conversation: previous_conversation,
        parent_subagent_session: previous_session,
        scope: "conversation",
        profile_key: profile_key,
        depth: index
      )

      previous_conversation = conversation
      previous_session = session
    end

    {
      conversation: previous_conversation,
      subagent_session: previous_session,
    }
  end
end
