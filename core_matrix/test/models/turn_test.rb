require "test_helper"

class TurnTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    agent_program_version = create_agent_program_version!(installation: installation, agent_program: agent_program)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    turn = Turn.create!(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.public_id.present?
    assert_equal turn, Turn.find_by_public_id!(turn.public_id)
  end

  test "enforces unique sequence numbers within a conversation" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    agent_program_version = create_agent_program_version!(installation: installation, agent_program: agent_program)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    Turn.create!(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    duplicate = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      sequence: 1,
      lifecycle_state: "queued",
      origin_kind: "automation_schedule",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
  end

  test "belongs to an agent program version and allows executor program to be nil" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    agent_program_version = create_agent_program_version!(installation: installation, agent_program: agent_program)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      executor_program: nil,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.valid?
    assert_equal :belongs_to, Turn.reflect_on_association(:agent_program_version).macro
    executor_program_association = Turn.reflect_on_association(:executor_program)

    assert_equal :belongs_to, executor_program_association.macro
    assert executor_program_association.options[:optional]
  end

  test "treats waiting as a non terminal lifecycle state" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation)
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    agent_program_version = create_agent_program_version!(installation: installation, agent_program: agent_program)
    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      sequence: 1,
      lifecycle_state: "waiting",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert turn.valid?
    refute turn.terminal?
  end

  test "requires the frozen program version to belong to the conversation program" do
    installation = create_installation!
    agent_program = create_agent_program!(installation: installation, key: "main-program")
    other_program = create_agent_program!(installation: installation, key: "other-program")
    user = create_user!(installation: installation)
    user_program_binding = create_user_program_binding!(
      installation: installation,
      user: user,
      agent_program: agent_program
    )
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_program_binding: user_program_binding
    )
    agent_program_version = create_agent_program_version!(installation: installation, agent_program: other_program)
    conversation = Conversation.create!(
      installation: installation,
      workspace: workspace,
      agent_program: agent_program,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )

    turn = Turn.new(
      installation: installation,
      conversation: conversation,
      agent_program_version: agent_program_version,
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      pinned_program_version_fingerprint: agent_program_version.fingerprint,
      feature_policy_snapshot: conversation.feature_policy_snapshot,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_not turn.valid?
    assert_includes turn.errors[:agent_program_version], "must belong to the conversation agent program"
  end
end
