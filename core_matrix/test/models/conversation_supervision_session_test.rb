require "test_helper"

class ConversationSupervisionSessionTest < ActiveSupport::TestCase
  test "generates a public id links the target conversation and stays ephemeral" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )

    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true },
      last_snapshot_at: Time.current
    )

    assert session.public_id.present?
    assert_equal session, ConversationSupervisionSession.find_by_public_id!(session.public_id)
    assert_equal conversation, session.target_conversation
    assert_equal context[:installation], session.installation
    assert_equal :ephemeral_observability, ConversationSupervisionSession.data_lifecycle_kind
    assert_equal 1, conversation.conversation_supervision_sessions.count
    assert_not_nil Conversation.reflect_on_association(:conversation_supervision_sessions)
  end

  test "requires installation to match the target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    other_installation = create_raw_installation!

    session = ConversationSupervisionSession.new(
      installation: other_installation,
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )

    assert_not session.valid?
    assert_includes session.errors[:target_conversation], "must belong to the same installation"
  end

  test "stamps closed_at when the session closes and clears it when reopened" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {}
    )

    travel_to(Time.utc(2026, 4, 9, 13, 0, 0)) do
      session.update!(lifecycle_state: "closed")
    end

    assert_equal Time.utc(2026, 4, 9, 13, 0, 0), session.closed_at

    session.update!(lifecycle_state: "open")

    assert_nil session.closed_at
  end

  test "requires duplicated owner context to match the target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    foreign = create_workspace_context!

    session = ConversationSupervisionSession.new(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )

    assert_not session.valid?
    assert_includes session.errors[:user], "must match the target conversation user"
    assert_includes session.errors[:workspace], "must match the target conversation workspace"
    assert_includes session.errors[:agent], "must match the target conversation agent"
  end

  private

  def create_raw_installation!
    now = Time.current
    sql = <<~SQL.squish
      INSERT INTO installations (name, bootstrap_state, global_settings, created_at, updated_at)
      VALUES (#{ApplicationRecord.connection.quote("Supervision Session Installation #{next_test_sequence}")},
              'bootstrapped',
              '{}',
              #{ApplicationRecord.connection.quote(now)},
              #{ApplicationRecord.connection.quote(now)})
      RETURNING id
    SQL
    installation_id = ApplicationRecord.connection.select_value(sql)
    Installation.find(installation_id)
  end
end
