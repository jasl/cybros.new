module Conversations
  class CreateFork
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(parent:, historical_anchor_message_id: nil, entry_policy_payload: nil)
      @parent = parent
      @historical_anchor_message_id = historical_anchor_message_id
      @entry_policy_payload = entry_policy_payload
    end

    def call
      conversation = build_child_conversation(
        parent: @parent,
        kind: "fork",
        historical_anchor_message_id: @historical_anchor_message_id,
        entry_policy_payload: resolved_entry_policy_payload
      )

      ApplicationRecord.transaction do
        Conversations::WithConversationEntryLock.call(
          conversation: @parent,
          record: conversation,
          retained_message: "must be retained before forking",
          active_message: "must be active before forking",
          closing_message: "must not create child conversations while close is in progress"
        ) do |parent|
          Conversations::AssertFeatureEnabled.call(
            conversation: parent,
            feature_id: "conversation_branching",
            record: conversation
          )
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

    private

    def resolved_entry_policy_payload
      return @entry_policy_payload if @entry_policy_payload.present?
      return unless Conversations::ManagedPolicy.call(conversation: @parent).fetch("managed", false)

      Conversation.normalize_entry_policy_payload(
        @parent.workspace_agent.entry_policy_payload,
        purpose: @parent.purpose
      )
    end
  end
end
