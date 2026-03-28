module Conversations
  class CreateThread
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(parent:, historical_anchor_message_id: nil, addressability: "owner_addressable")
      @parent = parent
      @historical_anchor_message_id = historical_anchor_message_id
      @addressability = addressability
    end

    def call
      ApplicationRecord.transaction do
        Conversations::WithChildConversationEntryLock.call(
          parent: @parent,
          entry_label: "threading"
        ) do |parent|
          conversation = build_child_conversation(
            parent: parent,
            kind: "thread",
            historical_anchor_message_id: @historical_anchor_message_id,
            addressability: @addressability
          )
          Conversations::ValidateHistoricalAnchor.call(
            parent: parent,
            kind: "thread",
            historical_anchor_message_id: @historical_anchor_message_id,
            record: conversation
          )

          conversation.save!

          initialize_child_conversation!(conversation: conversation, parent: parent)
        end
      end
    end
  end
end
