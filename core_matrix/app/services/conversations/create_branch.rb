module Conversations
  class CreateBranch
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(parent:, historical_anchor_message_id: nil)
      @parent = parent
      @historical_anchor_message_id = historical_anchor_message_id
    end

    def call
      ApplicationRecord.transaction do
        Conversations::WithChildConversationEntryLock.call(
          parent: @parent,
          entry_label: "branching"
        ) do |parent|
          conversation = build_child_conversation(
            parent: parent,
            kind: "branch",
            historical_anchor_message_id: @historical_anchor_message_id
          )
          anchor_message = Conversations::ValidateHistoricalAnchor.call(
            parent: parent,
            kind: conversation.kind,
            historical_anchor_message_id: @historical_anchor_message_id,
            record: conversation
          )
          conversation.save!

          initialize_child_conversation!(conversation: conversation, parent: parent)
          create_branch_prefix_import_for!(conversation, parent:, anchor_message:)
          conversation
        end
      end
    end

    def create_branch_prefix_import_for!(conversation, parent:, anchor_message:)
      Conversations::AddImport.call(
        conversation: conversation,
        kind: "branch_prefix",
        source_conversation: parent,
        source_message: anchor_message
      )
    end
  end
end
