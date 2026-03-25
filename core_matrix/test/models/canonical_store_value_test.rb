require "test_helper"

class CanonicalStoreValueTest < ActiveSupport::TestCase
  test "computes payload bytesize and caps values at 2 MiB" do
    exact_payload = {
      "type" => "string",
      "value" => "a" * (2.megabytes - { "type" => "string", "value" => "" }.to_json.bytesize),
    }
    exact_value = CanonicalStoreValue.new(typed_value_payload: exact_payload)

    oversized_payload = {
      "type" => "string",
      "value" => "a" * (2.megabytes + 1),
    }
    oversized_value = CanonicalStoreValue.new(typed_value_payload: oversized_payload)

    assert exact_value.valid?
    assert_operator exact_value.payload_bytesize, :<=, 2.megabytes

    assert oversized_value.invalid?
    assert_includes oversized_value.errors[:payload_bytesize], "must be less than or equal to 2097152"
  end
end
