require "test_helper"

module CanonicalStores
end

class CanonicalStores::ListKeysQueryTest < ActiveSupport::TestCase
  test "lists visible keys without loading value rows" do
    context = build_canonical_store_context!
    alpha = create_canonical_store_value!(typed_value_payload: { "type" => "string", "value" => "a" })
    beta = create_canonical_store_value!(typed_value_payload: { "type" => "string", "value" => "b" })
    first_snapshot = create_canonical_store_snapshot!(
      canonical_store: context[:canonical_store],
      snapshot_kind: "write",
      base_snapshot: context[:canonical_store_snapshot],
      depth: 1
    )
    create_canonical_store_entry!(
      canonical_store_snapshot: first_snapshot,
      key: "alpha",
      entry_kind: "set",
      canonical_store_value: alpha,
      value_type: "string",
      value_bytesize: alpha.payload_bytesize
    )
    second_snapshot = create_canonical_store_snapshot!(
      canonical_store: context[:canonical_store],
      snapshot_kind: "write",
      base_snapshot: first_snapshot,
      depth: 2
    )
    create_canonical_store_entry!(
      canonical_store_snapshot: second_snapshot,
      key: "beta",
      entry_kind: "set",
      canonical_store_value: beta,
      value_type: "string",
      value_bytesize: beta.payload_bytesize
    )
    third_snapshot = create_canonical_store_snapshot!(
      canonical_store: context[:canonical_store],
      snapshot_kind: "write",
      base_snapshot: second_snapshot,
      depth: 3
    )
    create_canonical_store_entry!(
      canonical_store_snapshot: third_snapshot,
      key: "beta",
      entry_kind: "tombstone"
    )
    context[:canonical_store_reference].update!(canonical_store_snapshot: third_snapshot)

    page = nil
    queries = capture_sql_queries do
      page = CanonicalStores::ListKeysQuery.call(
        reference_owner: context[:conversation],
        cursor: nil,
        limit: 20
      )
    end

    assert_equal 1, queries.size
    refute_match(/canonical_store_values/i, queries.first)
    assert_equal ["alpha"], page.items.map(&:key)
    assert_equal "string", page.items.first.value_type
    assert_equal alpha.payload_bytesize, page.items.first.value_bytesize
    refute page.items.first.respond_to?(:typed_value_payload)
  end

  test "paginates by stable key order" do
    context = build_canonical_store_context!
    %w[alpha beta gamma].each_with_index do |key, index|
      value = create_canonical_store_value!(typed_value_payload: { "type" => "string", "value" => key.upcase })
      base_snapshot = context[:canonical_store_reference].canonical_store_snapshot
      snapshot = create_canonical_store_snapshot!(
        canonical_store: context[:canonical_store],
        snapshot_kind: "write",
        base_snapshot: base_snapshot,
        depth: base_snapshot.depth + 1
      )
      create_canonical_store_entry!(
        canonical_store_snapshot: snapshot,
        key: key,
        entry_kind: "set",
        canonical_store_value: value,
        value_type: "string",
        value_bytesize: value.payload_bytesize,
        created_at: Time.current + index.seconds
      )
      context[:canonical_store_reference].update!(canonical_store_snapshot: snapshot)
    end

    first_page = CanonicalStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: nil,
      limit: 2
    )
    second_page = CanonicalStores::ListKeysQuery.call(
      reference_owner: context[:conversation],
      cursor: first_page.next_cursor,
      limit: 2
    )

    assert_equal %w[alpha beta], first_page.items.map(&:key)
    assert_equal "beta", first_page.next_cursor
    assert_equal ["gamma"], second_page.items.map(&:key)
    assert_nil second_page.next_cursor
  end
end
