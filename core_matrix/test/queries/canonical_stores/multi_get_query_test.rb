require "test_helper"

module CanonicalStores
end

class CanonicalStores::MultiGetQueryTest < ActiveSupport::TestCase
  test "preserves request order and batch-loads values" do
    context = build_canonical_store_context!
    customer_name = create_canonical_store_value!(typed_value_payload: { "type" => "string", "value" => "Acme China" })
    tone = create_canonical_store_value!(typed_value_payload: { "type" => "string", "value" => "direct" })
    first_snapshot = create_canonical_store_snapshot!(
      canonical_store: context[:canonical_store],
      snapshot_kind: "write",
      base_snapshot: context[:canonical_store_snapshot],
      depth: 1
    )
    create_canonical_store_entry!(
      canonical_store_snapshot: first_snapshot,
      key: "customer_name",
      entry_kind: "set",
      canonical_store_value: customer_name,
      value_type: "string",
      value_bytesize: customer_name.payload_bytesize
    )
    second_snapshot = create_canonical_store_snapshot!(
      canonical_store: context[:canonical_store],
      snapshot_kind: "write",
      base_snapshot: first_snapshot,
      depth: 2
    )
    create_canonical_store_entry!(
      canonical_store_snapshot: second_snapshot,
      key: "tone",
      entry_kind: "set",
      canonical_store_value: tone,
      value_type: "string",
      value_bytesize: tone.payload_bytesize
    )
    context[:canonical_store_reference].update!(canonical_store_snapshot: second_snapshot)

    result = nil
    assert_sql_query_count(2) do
      result = CanonicalStores::MultiGetQuery.call(
        reference_owner: context[:conversation],
        keys: %w[customer_name tone missing]
      )
    end

    assert_equal %w[customer_name tone missing], result.keys
    assert_equal "Acme China", result["customer_name"].typed_value_payload["value"]
    assert_equal "direct", result["tone"].typed_value_payload["value"]
    assert_nil result["missing"]
  end
end
