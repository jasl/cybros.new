require "test_helper"

module LineageStores
end

class LineageStores::SetTest < ActiveSupport::TestCase
  test "creates a new write snapshot and moves the conversation reference" do
    context = build_lineage_store_context!

    assert_difference("LineageStoreSnapshot.count", +1) do
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "tone",
        typed_value_payload: { "type" => "string", "value" => "direct" }
      )
    end

    visible = LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "tone")

    assert_equal "direct", visible.typed_value_payload["value"]
    assert_equal 1, context[:conversation].reload.lineage_store_reference.lineage_store_snapshot.depth
  end

  test "identical set is a no-op" do
    context = build_lineage_store_context!
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )

    assert_no_difference("LineageStoreSnapshot.count") do
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "tone",
        typed_value_payload: { "type" => "string", "value" => "direct" }
      )
    end
  end

  test "compacts before writing once the snapshot chain reaches depth 32" do
    context = build_lineage_store_context!
    32.times do |index|
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "key_#{index}",
        typed_value_payload: { "type" => "string", "value" => "value_#{index}" }
      )
    end

    assert_equal 32, context[:conversation].reload.lineage_store_reference.lineage_store_snapshot.depth

    assert_difference("LineageStoreSnapshot.count", +2) do
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "overflow",
        typed_value_payload: { "type" => "string", "value" => "after_compaction" }
      )
    end

    current_snapshot = context[:conversation].reload.lineage_store_reference.lineage_store_snapshot
    assert_equal "write", current_snapshot.snapshot_kind
    assert_equal 1, current_snapshot.depth
    assert_equal "compaction", current_snapshot.base_snapshot.snapshot_kind
  end

  test "rechecks retained state after acquiring the conversation lock" do
    context = build_lineage_store_context!
    conversation = context[:conversation]
    request_deletion_during_lock!(conversation)

    assert_no_difference("LineageStoreSnapshot.count") do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        LineageStores::Set.call(
          conversation: conversation,
          key: "tone",
          typed_value_payload: { "type" => "string", "value" => "direct" }
        )
      end

      assert_includes error.record.errors[:deletion_state], "must be retained for conversation-local writes"
    end

    assert_nil LineageStores::GetQuery.call(reference_owner: conversation, key: "tone")
  end

  test "rejects writes for archived conversations" do
    context = build_lineage_store_context!
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "tone",
        typed_value_payload: { "type" => "string", "value" => "direct" }
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active for conversation-local writes"
  end

  private

  def request_deletion_during_lock!(conversation)
    injected = false

    conversation.singleton_class.prepend(Module.new do
      define_method(:lock!) do |*args, **kwargs|
        unless injected
          injected = true
          pool = self.class.connection_pool
          connection = pool.checkout

          begin
            deleted_at = Time.current

            connection.execute(<<~SQL.squish)
              UPDATE conversations
              SET deletion_state = 'pending_delete',
                  deleted_at = #{connection.quote(deleted_at)},
                  updated_at = #{connection.quote(deleted_at)}
              WHERE id = #{connection.quote(id)}
            SQL
          ensure
            pool.checkin(connection)
          end
        end

        super(*args, **kwargs)
      end
    end)
  end
end
