module LineageStores
  class BootstrapForConversation
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return @conversation.lineage_store_reference if @conversation.lineage_store_reference.present?

      ApplicationRecord.transaction do
        lineage_store = LineageStore.create!(
          installation: @conversation.installation,
          workspace: @conversation.workspace,
          root_conversation: @conversation
        )
        snapshot = LineageStoreSnapshot.create!(
          lineage_store: lineage_store,
          snapshot_kind: "root",
          depth: 0
        )

        reference = LineageStoreReference.create!(
          lineage_store_snapshot: snapshot,
          owner: @conversation
        )
        @conversation.association(:lineage_store_reference).reset
        reference
      end
    end
  end
end
