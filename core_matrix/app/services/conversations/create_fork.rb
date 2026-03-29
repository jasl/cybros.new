module Conversations
  class CreateFork
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
      conversation = build_child_conversation(
        parent: @parent,
        kind: "fork",
        historical_anchor_message_id: @historical_anchor_message_id,
        addressability: @addressability
      )

      ApplicationRecord.transaction do
        Conversations::WithConversationEntryLock.call(
          conversation: @parent,
          record: conversation,
          retained_message: "must be retained before forking",
          active_message: "must be active before forking",
          closing_message: "must not create child conversations while close is in progress"
        ) do |parent|
          refresh_child_conversation_from_parent!(conversation:, parent:)
          Conversations::ValidateHistoricalAnchor.call(
            parent: parent,
            kind: "fork",
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
