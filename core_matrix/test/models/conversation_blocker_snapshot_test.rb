require "test_helper"

class ConversationBlockerSnapshotTest < ActiveSupport::TestCase
  test "derives close-state predicates from one blocker snapshot" do
    snapshot = ConversationBlockerSnapshot.new(
      retained: true,
      active: true,
      closing: false,
      running_background_process_count: 1,
      degraded_close_count: 1,
      root_lineage_store_blocker: true
    )

    assert snapshot.mainline_clear?
    assert snapshot.tail_pending?
    assert snapshot.tail_degraded?
    assert snapshot.dependency_blocked?
    assert snapshot.mutable_for_live_mutation?
    assert_equal 1, snapshot.close_summary.dig(:tail, :running_background_process_count)
    assert_equal(
      {
        descendant_lineage_blockers: 0,
        root_lineage_store_blocker: true,
        variable_provenance_blocker: false,
        import_provenance_blocker: false,
      },
      snapshot.dependency_blockers.to_h
    )
  end

  test "marks live mutation unavailable once the conversation is no longer mutable" do
    snapshot = ConversationBlockerSnapshot.new(
      retained: true,
      active: true,
      closing: true
    )

    refute snapshot.mutable_for_live_mutation?
  end
end
