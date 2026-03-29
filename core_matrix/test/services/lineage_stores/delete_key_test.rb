require "test_helper"

module LineageStores
end

class LineageStores::DeleteKeyTest < ActiveSupport::TestCase
  test "writes a tombstone snapshot for an existing key" do
    context = build_lineage_store_context!
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )

    assert_difference("LineageStoreSnapshot.count", +1) do
      LineageStores::DeleteKey.call(conversation: context[:conversation], key: "tone")
    end

    assert_nil LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "tone")
    assert_equal "tombstone",
      context[:conversation].reload.lineage_store_reference
        .lineage_store_snapshot
        .lineage_store_entries
        .sole
        .entry_kind
  end

  test "missing delete is a no-op" do
    context = build_lineage_store_context!

    assert_no_difference("LineageStoreSnapshot.count") do
      LineageStores::DeleteKey.call(conversation: context[:conversation], key: "missing")
    end
  end

  test "rechecks retained state after acquiring the conversation lock" do
    context = build_lineage_store_context!
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )
    conversation = context[:conversation]
    request_deletion_during_lock!(conversation)

    assert_no_difference("LineageStoreSnapshot.count") do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        LineageStores::DeleteKey.call(conversation: conversation, key: "tone")
      end

      assert_includes error.record.errors[:deletion_state], "must be retained for conversation-local writes"
    end

    assert_equal "direct",
      LineageStores::GetQuery.call(reference_owner: conversation, key: "tone").typed_value_payload["value"]
  end

  test "rejects deletes while close is in progress" do
    context = build_lineage_store_context!
    LineageStores::Set.call(
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" }
    )
    ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      LineageStores::DeleteKey.call(conversation: context[:conversation], key: "tone")
    end

    assert_includes error.record.errors[:base], "must not mutate conversation state while close is in progress"
  end

  test "deep-chain deletes compact first and keep the latest surviving values visible" do
    context = build_lineage_store_context!

    16.times do |index|
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "alpha",
        typed_value_payload: { "type" => "string", "value" => "alpha_#{index}" }
      )
      LineageStores::Set.call(
        conversation: context[:conversation],
        key: "beta",
        typed_value_payload: { "type" => "string", "value" => "beta_#{index}" }
      )
    end

    reference = context[:conversation].reload.lineage_store_reference
    latest_alpha_value_id = value_id_for(reference:, key: "alpha")
    latest_beta_value_id = value_id_for(reference:, key: "beta")

    assert_equal 32, reference.lineage_store_snapshot.depth

    assert_difference("LineageStoreSnapshot.count", +2) do
      LineageStores::DeleteKey.call(conversation: context[:conversation], key: "beta")
    end

    current_snapshot = context[:conversation].reload.lineage_store_reference.lineage_store_snapshot
    compaction_snapshot = current_snapshot.base_snapshot

    assert_equal "write", current_snapshot.snapshot_kind
    assert_equal 1, current_snapshot.depth
    assert_equal "compaction", compaction_snapshot.snapshot_kind
    assert_equal %w[alpha beta], compaction_snapshot.lineage_store_entries.order(:key).pluck(:key)
    assert_equal latest_alpha_value_id, compaction_snapshot.lineage_store_entries.find_by!(key: "alpha").lineage_store_value_id
    assert_equal latest_beta_value_id, compaction_snapshot.lineage_store_entries.find_by!(key: "beta").lineage_store_value_id
    assert_equal ["beta"], current_snapshot.lineage_store_entries.order(:key).pluck(:key)
    assert_equal "tombstone", current_snapshot.lineage_store_entries.sole.entry_kind
    assert_equal "alpha_15", LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "alpha").typed_value_payload.fetch("value")
    assert_nil LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "beta")
  end

  private

  def value_id_for(reference:, key:)
    LineageStoreEntry
      .joins(:lineage_store_snapshot)
      .where(
        lineage_store_snapshots: { lineage_store_id: reference.lineage_store_snapshot.lineage_store_id },
        key: key,
        entry_kind: "set"
      )
      .order(id: :desc)
      .pick(:lineage_store_value_id)
  end

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
