require "test_helper"

class SubagentSessions::OwnedTreeTest < ActiveSupport::TestCase
  test "collects nested owned sessions through subagent ownership chains" do
    context = create_workspace_context!
    root_conversation = create_root_conversation!(context: context)
    first_session = create_owned_subagent_session!(
      context: context,
      owner_conversation: root_conversation
    )
    second_session = create_owned_subagent_session!(
      context: context,
      owner_conversation: first_session.conversation
    )
    third_session = create_owned_subagent_session!(
      context: context,
      owner_conversation: second_session.conversation
    )
    unrelated_owner = create_root_conversation!(context: context)
    create_owned_subagent_session!(
      context: context,
      owner_conversation: unrelated_owner
    )

    tree = SubagentSessions::OwnedTree.new(owner_conversation: root_conversation)

    assert_equal [first_session.id, second_session.id, third_session.id], tree.sessions.map(&:id)
    assert_equal [first_session.id, second_session.id, third_session.id], tree.session_ids
    assert_equal [first_session.conversation_id, second_session.conversation_id, third_session.conversation_id], tree.conversation_ids
  end

  test "loads nested owned sessions with a single recursive query" do
    context = create_workspace_context!
    root_conversation = create_root_conversation!(context: context)
    parent_session = create_owned_subagent_session!(
      context: context,
      owner_conversation: root_conversation
    )
    create_owned_subagent_session!(
      context: context,
      owner_conversation: parent_session.conversation
    )

    queries = capture_sql_queries do
      SubagentSessions::OwnedTree.new(owner_conversation: root_conversation).sessions
    end

    assert_operator queries.length, :<=, 1, "Expected owned tree lookup to stay within 1 SQL query, got #{queries.length}:\n#{queries.join("\n")}"
  end

  private

  def create_root_conversation!(context:)
    Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
  end

  def create_owned_subagent_session!(context:, owner_conversation:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version],
      addressability: "agent_addressable"
    )

    SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
  end
end
