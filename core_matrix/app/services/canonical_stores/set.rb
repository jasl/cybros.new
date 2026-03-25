module CanonicalStores
  class Set
    include Conversations::RetentionGuard

    MAX_SNAPSHOT_DEPTH = 32

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, key:, typed_value_payload:)
      @conversation = conversation
      @key = key.to_s
      @typed_value_payload = typed_value_payload
    end

    def call
      ApplicationRecord.transaction do
        @conversation.lock!
        ensure_conversation_retained!(@conversation, message: "must be retained for conversation-local writes")
        reference = current_reference!
        reference.lock!

        current_value = CanonicalStores::GetQuery.call(reference_owner: @conversation, key: @key)
        return current_value if current_value&.typed_value_payload == @typed_value_payload

        reference = compact_if_needed!(reference)
        value = find_or_create_value!
        current_snapshot = reference.canonical_store_snapshot
        write_snapshot = CanonicalStoreSnapshot.create!(
          canonical_store: current_snapshot.canonical_store,
          base_snapshot: current_snapshot,
          snapshot_kind: "write",
          depth: current_snapshot.depth + 1
        )
        CanonicalStoreEntry.create!(
          canonical_store_snapshot: write_snapshot,
          key: @key,
          entry_kind: "set",
          canonical_store_value: value,
          value_type: @typed_value_payload["type"],
          value_bytesize: value.payload_bytesize
        )
        reference.update!(canonical_store_snapshot: write_snapshot)

        CanonicalStores::VisibleValue.new(
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

    def compact_if_needed!(reference)
      return reference unless reference.canonical_store_snapshot.depth >= MAX_SNAPSHOT_DEPTH

      CanonicalStores::CompactSnapshot.call(conversation: @conversation)
      reference.reload
    end

    def current_reference!
      @conversation.canonical_store_reference ||
        raise(ActiveRecord::RecordNotFound, "canonical store reference is missing")
    end

    def find_or_create_value!
      candidate = CanonicalStoreValue.new(typed_value_payload: @typed_value_payload)
      raise ActiveRecord::RecordInvalid, candidate unless candidate.valid?

      existing = CanonicalStoreValue
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
