module LineageStores
  class Set
    include LineageStores::WriteSupport

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, key:, typed_value_payload:)
      @conversation = conversation
      @key = key.to_s
      @typed_value_payload = typed_value_payload
    end

    def call
      with_locked_reference_for_write do |_conversation, reference|
        current_value = LineageStores::GetQuery.call(reference_owner: @conversation, key: @key)
        return current_value if current_value&.typed_value_payload == @typed_value_payload

        value = find_or_create_value!
        write_snapshot = append_write_entry!(
          reference: reference,
          entry_attributes: {
            key: @key,
            entry_kind: "set",
            lineage_store_value: value,
            value_type: @typed_value_payload["type"],
            value_bytesize: value.payload_bytesize,
          }
        )

        LineageStores::VisibleValue.new(
          key: @key,
          typed_value_payload: value.typed_value_payload,
          value_type: @typed_value_payload["type"],
          value_bytesize: value.payload_bytesize,
          created_at: write_snapshot.created_at,
          updated_at: write_snapshot.updated_at
        )
      end
    end

    private

    def find_or_create_value!
      candidate = LineageStoreValue.new(typed_value_payload: @typed_value_payload)
      raise ActiveRecord::RecordInvalid, candidate unless candidate.valid?

      existing = LineageStoreValue
        .where(
          payload_sha256: candidate.payload_sha256,
          payload_bytesize: candidate.payload_bytesize
        )
        .find { |value| value.typed_value_payload == @typed_value_payload }
      return existing if existing.present?

      candidate.save!
      candidate
    end
  end
end
