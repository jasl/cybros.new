require "test_helper"

module LineageStores
end

class LineageStores::GetQueryTest < ActiveSupport::TestCase
  test "returns nil when the owner has no lineage reference" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    assert_nil LineageStores::GetQuery.call(reference_owner: conversation, key: "tone")
  end

  test "returns the newest visible value for a key" do
    context = build_lineage_store_context!
    value = create_lineage_store_value!(typed_value_payload: { "type" => "string", "value" => "direct" })
    write_snapshot = create_lineage_store_snapshot!(
      lineage_store: context[:lineage_store],
      snapshot_kind: "write",
      base_snapshot: context[:lineage_store_snapshot],
      depth: 1
    )
    create_lineage_store_entry!(
      lineage_store_snapshot: write_snapshot,
      key: "tone",
      entry_kind: "set",
      lineage_store_value: value,
      value_type: "string",
      value_bytesize: value.payload_bytesize
    )
    context[:lineage_store_reference].update!(lineage_store_snapshot: write_snapshot)

    result = nil
    assert_sql_query_count(1) do
      result = LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "tone")
    end

    assert_equal "tone", result.key
    assert_equal({ "type" => "string", "value" => "direct" }, result.typed_value_payload)
    assert_equal "string", result.value_type
    assert_equal value.payload_bytesize, result.value_bytesize
  end

  test "returns missing when newest visible entry is a tombstone" do
    context = build_lineage_store_context!
    value = create_lineage_store_value!(typed_value_payload: { "type" => "string", "value" => "direct" })
    set_snapshot = create_lineage_store_snapshot!(
      lineage_store: context[:lineage_store],
      snapshot_kind: "write",
      base_snapshot: context[:lineage_store_snapshot],
      depth: 1
    )
    create_lineage_store_entry!(
      lineage_store_snapshot: set_snapshot,
      key: "tone",
      entry_kind: "set",
      lineage_store_value: value,
      value_type: "string",
      value_bytesize: value.payload_bytesize
    )
    tombstone_snapshot = create_lineage_store_snapshot!(
      lineage_store: context[:lineage_store],
      snapshot_kind: "write",
      base_snapshot: set_snapshot,
      depth: 2
    )
    create_lineage_store_entry!(
      lineage_store_snapshot: tombstone_snapshot,
      key: "tone",
      entry_kind: "tombstone"
    )
    context[:lineage_store_reference].update!(lineage_store_snapshot: tombstone_snapshot)

    assert_nil LineageStores::GetQuery.call(reference_owner: context[:conversation], key: "tone")
  end
end
