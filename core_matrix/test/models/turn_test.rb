require "test_helper"

class TurnTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )
    agent_snapshot = create_agent_snapshot!(installation: installation, agent: agent)
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
      agent_snapshot: agent_snapshot,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
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
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )
    agent_snapshot = create_agent_snapshot!(installation: installation, agent: agent)
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
      agent_snapshot: agent_snapshot,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    duplicate = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_snapshot: agent_snapshot,
      sequence: 1,
      lifecycle_state: "queued",
      origin_kind: "automation_schedule",
      origin_payload: {},
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
  end

  test "belongs to an agent snapshot and allows execution runtime to be nil" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )
    agent_snapshot = create_agent_snapshot!(installation: installation, agent: agent)
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
      agent_snapshot: agent_snapshot,
      execution_runtime: nil,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.valid?
    assert_equal :belongs_to, Turn.reflect_on_association(:agent_snapshot).macro
    execution_runtime_association = Turn.reflect_on_association(:execution_runtime)

    assert_equal :belongs_to, execution_runtime_association.macro
    assert execution_runtime_association.options[:optional]
  end

  test "treats waiting as a non terminal lifecycle state" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent: agent,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    agent_snapshot = create_agent_snapshot!(installation: installation, agent: agent)
    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_snapshot: agent_snapshot,
      sequence: 1,
      lifecycle_state: "waiting",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.valid?
    refute turn.terminal?
  end

  test "requires the frozen agent snapshot to belong to the conversation program" do
    installation = create_installation!
    agent = create_agent!(installation: installation, key: "main-program")
    other_program = create_agent!(installation: installation, key: "other-program")
    user = create_user!(installation: installation)
    user_agent_binding = create_user_agent_binding!(
      installation: installation,
      user: user,
      agent: agent
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: user_agent_binding
    )
    agent_snapshot = create_agent_snapshot!(installation: installation, agent: other_program)
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
      agent_snapshot: agent_snapshot,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not turn.valid?
    assert_includes turn.errors[:agent_snapshot], "must belong to the conversation agent"
  end
end
