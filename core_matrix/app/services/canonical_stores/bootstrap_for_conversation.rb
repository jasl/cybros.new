module CanonicalStores
  class BootstrapForConversation
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return @conversation.canonical_store_reference if @conversation.canonical_store_reference.present?

      ApplicationRecord.transaction do
        canonical_store = CanonicalStore.create!(
          installation: @conversation.installation,
          workspace: @conversation.workspace,
          root_conversation: @conversation
        )
        snapshot = CanonicalStoreSnapshot.create!(
          canonical_store: canonical_store,
          snapshot_kind: "root",
          depth: 0
        )

        reference = CanonicalStoreReference.create!(
          canonical_store_snapshot: snapshot,
          owner: @conversation
        )
        @conversation.association(:canonical_store_reference).reset
        reference
      end
    end
  end
end
