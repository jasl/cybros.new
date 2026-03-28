module Conversations
  class CreateCheckpoint
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(parent:, historical_anchor_message_id: nil)
      @parent = parent
      @historical_anchor_message_id = historical_anchor_message_id
    end

    def call
      conversation = build_child_conversation(
        parent: @parent,
        kind: "checkpoint",
        historical_anchor_message_id: @historical_anchor_message_id
      )

      ApplicationRecord.transaction do
        Conversations::WithConversationEntryLock.call(
          conversation: @parent,
          record: conversation,
          retained_message: "must be retained before checkpointing",
          active_message: "must be active before checkpointing",
          closing_message: "must not create child conversations while close is in progress"
        ) do |parent|
          refresh_child_conversation_from_parent!(conversation:, parent:)
          Conversations::ValidateHistoricalAnchor.call(
            parent: parent,
            kind: "checkpoint",
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
