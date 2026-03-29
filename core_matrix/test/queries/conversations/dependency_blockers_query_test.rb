require "test_helper"

class Conversations::DependencyBlockersQueryTest < ActiveSupport::TestCase
  test "projects dependency blockers from the canonical blocker snapshot" do
    context = build_agent_control_context!
    conversation = context[:conversation]

    Conversations::CreateFork.call(parent: conversation)

    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: conversation)
    blockers = Conversations::DependencyBlockersQuery.call(conversation: conversation)

    assert_equal snapshot.dependency_blockers.to_h, blockers.to_h
    assert_equal snapshot.dependency_blockers.blocked?, blockers.blocked?
  end
end
