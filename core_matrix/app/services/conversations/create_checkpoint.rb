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
        Conversations::WithMutableStateLock.call(
          conversation: @parent,
          record: @parent,
          retained_message: "must be retained before checkpointing",
          active_message: "must be active before checkpointing",
          closing_message: "must not create child conversations while close is in progress"
        ) do |parent|
          Conversations::ValidateHistoricalAnchor.call(
            parent: parent,
            kind: "checkpoint",
            historical_anchor_message_id: @historical_anchor_message_id,
            record: parent
          )

          conversation = Conversation.create!(
            installation: parent.installation,
            workspace: parent.workspace,
            execution_environment: parent.execution_environment,
            agent_deployment: parent.agent_deployment,
            parent_conversation: parent,
            kind: "checkpoint",
            purpose: parent.purpose,
            lifecycle_state: "active",
            historical_anchor_message_id: @historical_anchor_message_id
          )

          create_closures_for!(conversation, parent:)
          create_canonical_store_reference_for!(conversation, parent:)
          Conversations::RefreshRuntimeContract.call(conversation: conversation)
          conversation
        end
      end
    end

    private

    def create_closures_for!(conversation, parent:)
      ConversationClosure.where(descendant_conversation: parent).find_each do |closure|
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

    def create_canonical_store_reference_for!(conversation, parent:)
      parent_reference = parent.canonical_store_reference ||
        raise(ActiveRecord::RecordNotFound, "canonical store reference is missing")

      CanonicalStoreReference.create!(
        owner: conversation,
        canonical_store_snapshot: parent_reference.canonical_store_snapshot
      )
    end
  end
end
