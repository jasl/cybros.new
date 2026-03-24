module Conversations
  class CreateCheckpoint
    def self.call(...)
      new(...).call
    end

    def initialize(parent:, historical_anchor_message_id: nil)
      @parent = parent
      @historical_anchor_message_id = historical_anchor_message_id
    end

    def call
      ApplicationRecord.transaction do
        conversation = Conversation.create!(
          installation: @parent.installation,
          workspace: @parent.workspace,
          parent_conversation: @parent,
          kind: "checkpoint",
          purpose: @parent.purpose,
          lifecycle_state: "active",
          historical_anchor_message_id: @historical_anchor_message_id
        )

        create_closures_for!(conversation)
        conversation
      end
    end

    private

    def create_closures_for!(conversation)
      ConversationClosure.where(descendant_conversation: @parent).find_each do |closure|
        ConversationClosure.create!(
          installation: conversation.installation,
          ancestor_conversation: closure.ancestor_conversation,
          descendant_conversation: conversation,
          depth: closure.depth + 1
        )
      end

      ConversationClosure.create!(
        installation: conversation.installation,
        ancestor_conversation: conversation,
        descendant_conversation: conversation,
        depth: 0
      )
    end
  end
end
