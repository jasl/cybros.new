require "test_helper"

module LineageStores
end

class LineageStores::ListKeysQueryTest < ActiveSupport::TestCase
  test "returns an empty page when the owner has no lineage reference" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    page = LineageStores::ListKeysQuery.call(
      reference_owner: conversation,
      cursor: nil,
      limit: 20
    )

    assert_empty page.items
    assert_nil page.next_cursor
  end

  test "lists visible keys without loading value rows" do
    context = build_lineage_store_context!
    alpha = create_lineage_store_value!(typed_value_payload: { "type" => "string", "value" => "a" })
    beta = create_lineage_store_value!(typed_value_payload: { "type" => "string", "value" => "b" })
    first_snapshot = create_lineage_store_snapshot!(
      lineage_store: context[:lineage_store],
      snapshot_kind: "write",
      base_snapshot: context[:lineage_store_snapshot],
      depth: 1
    )
    create_lineage_store_entry!(
      lineage_store_snapshot: first_snapshot,
      key: "alpha",
      entry_kind: "set",
      lineage_store_value: alpha,
      value_type: "string",
      value_bytesize: alpha.payload_bytesize
    )
    second_snapshot = create_lineage_store_snapshot!(
      lineage_store: context[:lineage_store],
      snapshot_kind: "write",
      base_snapshot: first_snapshot,
      depth: 2
    )
    create_lineage_store_entry!(
      lineage_store_snapshot: second_snapshot,
      key: "beta",
      entry_kind: "set",
      lineage_store_value: beta,
      value_type: "string",
      value_bytesize: beta.payload_bytesize
    )
    third_snapshot = create_lineage_store_snapshot!(
      lineage_store: context[:lineage_store],
      snapshot_kind: "write",
      base_snapshot: second_snapshot,
      depth: 3
    )
    create_lineage_store_entry!(
      lineage_store_snapshot: third_snapshot,
      key: "beta",
      entry_kind: "tombstone"
    )
    context[:lineage_store_reference].update!(lineage_store_snapshot: third_snapshot)

    page = nil
    queries = capture_sql_queries do
      page = LineageStores::ListKeysQuery.call(
        reference_owner: context[:conversation],
        cursor: nil,
        limit: 20
      )
    end

    assert_equal 1, queries.size
    refute_match(/lineage_store_values/i, queries.first)
    assert_equal ["alpha"], page.items.map(&:key)
    assert_equal "string", page.items.first.value_type
    assert_equal alpha.payload_bytesize, page.items.first.value_bytesize
    refute page.items.first.respond_to?(:typed_value_payload)
  end

  test "paginates by stable key order" do
    context = build_lineage_store_context!
    %w[alpha beta gamma].each_with_index do |key, index|
      value = create_lineage_store_value!(typed_value_payload: { "type" => "string", "value" => key.upcase })
      base_snapshot = context[:lineage_store_reference].lineage_store_snapshot
      snapshot = create_lineage_store_snapshot!(
        lineage_store: context[:lineage_store],
        snapshot_kind: "write",
        base_snapshot: base_snapshot,
        depth: base_snapshot.depth + 1
      )
      create_lineage_store_entry!(
        lineage_store_snapshot: snapshot,
        key: key,
        entry_kind: "set",
        lineage_store_value: value,
        value_type: "string",
        value_bytesize: value.payload_bytesize,
        created_at: Time.current + index.seconds
      )
      context[:lineage_store_reference].update!(lineage_store_snapshot: snapshot)
    end

    first_page = LineageStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: nil,
      limit: 2
    )
    second_page = LineageStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: first_page.next_cursor,
      limit: 2
    )

    assert_equal %w[alpha beta], first_page.items.map(&:key)
    assert_equal "beta", first_page.next_cursor
    assert_equal ["gamma"], second_page.items.map(&:key)
    assert_nil second_page.next_cursor
  end

  test "applies an exclusive cursor and clamps invalid limits" do
    context = build_lineage_store_context!
    %w[alpha beta gamma].each do |key|
      value = create_lineage_store_value!(typed_value_payload: { "type" => "string", "value" => key.upcase })
      base_snapshot = context[:lineage_store_reference].lineage_store_snapshot
      snapshot = create_lineage_store_snapshot!(
        lineage_store: context[:lineage_store],
        snapshot_kind: "write",
        base_snapshot: base_snapshot,
        depth: base_snapshot.depth + 1
      )
      create_lineage_store_entry!(
        lineage_store_snapshot: snapshot,
        key: key,
        entry_kind: "set",
        lineage_store_value: value,
        value_type: "string",
        value_bytesize: value.payload_bytesize
      )
      context[:lineage_store_reference].update!(lineage_store_snapshot: snapshot)
    end

    first_page = LineageStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: "alpha",
      limit: 0
    )
    second_page = LineageStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: first_page.next_cursor,
      limit: "not-a-number"
    )

    assert_equal ["beta"], first_page.items.map(&:key)
    assert_equal "beta", first_page.next_cursor
    assert_equal ["gamma"], second_page.items.map(&:key)
    assert_nil second_page.next_cursor
  end
end
