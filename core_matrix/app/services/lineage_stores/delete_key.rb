module LineageStores
  class DeleteKey
    include LineageStores::WriteSupport

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, key:)
      @conversation = conversation
      @key = key.to_s
    end

    def call
      with_locked_reference_for_write do |_conversation, reference|
        return if LineageStores::GetQuery.call(reference_owner: @conversation, key: @key).blank?

        append_write_entry!(
          reference: reference,
          entry_attributes: {
            key: @key,
            entry_kind: "tombstone",
          }
        )
      end
    end
  end
end
