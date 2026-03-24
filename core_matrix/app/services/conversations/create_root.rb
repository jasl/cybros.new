module Conversations
  class CreateRoot
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:)
      @workspace = workspace
    end

    def call
      ApplicationRecord.transaction do
        conversation = Conversation.create!(
          installation: @workspace.installation,
          workspace: @workspace,
          kind: "root",
          purpose: "interactive",
          lifecycle_state: "active"
        )

        ConversationClosure.create!(
          installation: conversation.installation,
          ancestor_conversation: conversation,
          descendant_conversation: conversation,
          depth: 0
        )

        conversation
      end
    end
  end
end
