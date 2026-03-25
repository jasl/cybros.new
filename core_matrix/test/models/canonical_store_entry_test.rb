require "test_helper"

class CanonicalStoreEntryTest < ActiveSupport::TestCase
  test "enforces key byte length, entry kind, and per-snapshot uniqueness" do
    context = create_workspace_context!
    canonical_store = create_canonical_store!(workspace: context[:workspace])
    snapshot = create_canonical_store_snapshot!(canonical_store: canonical_store, snapshot_kind: "root")
    value = create_canonical_store_value!(typed_value_payload: { "type" => "string", "value" => "direct" })

    create_canonical_store_entry!(
      canonical_store_snapshot: snapshot,
      key: "tone",
      entry_kind: "set",
      canonical_store_value: value,
      value_type: "string",
      value_bytesize: value.payload_bytesize
    )

    duplicate = CanonicalStoreEntry.new(
      canonical_store_snapshot: snapshot,
      key: "tone",
      entry_kind: "set",
      canonical_store_value: value,
      value_type: "string",
      value_bytesize: value.payload_bytesize
    )
    tombstone_with_value = CanonicalStoreEntry.new(
      canonical_store_snapshot: snapshot,
      key: "deleted",
      entry_kind: "tombstone",
      canonical_store_value: value
    )
    set_without_value = CanonicalStoreEntry.new(
      canonical_store_snapshot: snapshot,
      key: "missing-value",
      entry_kind: "set"
    )
    multibyte_key = "你" * 43
    oversized_key = CanonicalStoreEntry.new(
      canonical_store_snapshot: snapshot,
      key: multibyte_key,
      entry_kind: "tombstone"
    )

    assert duplicate.invalid?
    assert_includes duplicate.errors[:key], "has already been taken"

    assert tombstone_with_value.invalid?
    assert_includes tombstone_with_value.errors[:canonical_store_value], "must be blank for tombstone entries"

    assert set_without_value.invalid?
    assert_includes set_without_value.errors[:canonical_store_value], "must exist for set entries"

    assert_equal 129, multibyte_key.bytesize
    assert oversized_key.invalid?
    assert_includes oversized_key.errors[:key], "must be between 1 and 128 bytes"
  end
end
