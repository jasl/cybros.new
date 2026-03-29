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
      conversation = build_child_conversation(
        parent: @parent,
        kind: "branch",
        historical_anchor_message_id: @historical_anchor_message_id
      )

      ApplicationRecord.transaction do
        Conversations::WithConversationEntryLock.call(
          conversation: @parent,
          record: conversation,
          retained_message: "must be retained before branching",
          active_message: "must be active before branching",
          closing_message: "must not create child conversations while close is in progress"
        ) do |parent|
          Conversations::AssertFeatureEnabled.call(
            conversation: parent,
            feature_id: "conversation_branching",
            record: conversation
          )
          refresh_child_conversation_from_parent!(conversation:, parent:)
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
