require "test_helper"

class TurnTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(installation: installation, user: user, user_agent_binding: user_agent_binding)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    turn = Turn.create!(
      installation: installation,
      conversation: conversation,
      agent_definition_version: agent_definition_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.public_id.present?
    assert_equal turn, Turn.find_by_public_id!(turn.public_id)
  end

  test "enforces unique sequence numbers within a conversation" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(installation: installation, user: user, user_agent_binding: user_agent_binding)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    Turn.create!(
      installation: installation,
      conversation: conversation,
      agent_definition_version: agent_definition_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    duplicate = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_definition_version: agent_definition_version,
      sequence: 1,
      lifecycle_state: "queued",
      origin_kind: "automation_schedule",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
  end

  test "belongs to a definition version and allows execution runtime to be nil" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(installation: installation, user: user, user_agent_binding: user_agent_binding)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_definition_version: agent_definition_version,
      execution_runtime: nil,
      execution_runtime_version: nil,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.valid?
    assert_equal :belongs_to, Turn.reflect_on_association(:agent_definition_version).macro
    assert_equal :belongs_to, Turn.reflect_on_association(:execution_runtime).macro
    assert Turn.reflect_on_association(:execution_runtime).options[:optional]
    assert_equal :belongs_to, Turn.reflect_on_association(:execution_runtime_version).macro
    assert Turn.reflect_on_association(:execution_runtime_version).options[:optional]
  end

  test "treats waiting as a non terminal lifecycle state" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(installation: installation, user: user, user_agent_binding: user_agent_binding)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_definition_version: agent_definition_version,
      sequence: 1,
      lifecycle_state: "waiting",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.valid?
    refute turn.terminal?
  end

  test "requires the frozen definition version to belong to the conversation agent" do
    installation = create_installation!
    agent = create_agent!(installation: installation, key: "main-agent")
    other_agent = create_agent!(installation: installation, key: "other-agent")
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(installation: installation, user: user, user_agent_binding: user_agent_binding)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: other_agent)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_definition_version: agent_definition_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      agent_config_version: 1,
      agent_config_content_fingerprint: "cfg-#{next_test_sequence}",
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not turn.valid?
    assert_includes turn.errors[:agent_definition_version], "must belong to the conversation agent"
  end
end
