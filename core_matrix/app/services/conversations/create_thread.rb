module Conversations
  class CreateThread
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
        Conversations::WithMutableStateLock.call(
          conversation: @parent,
          record: @parent,
          retained_message: "must be retained before threading",
          active_message: "must be active before threading",
          closing_message: "must not create child conversations while close is in progress"
        ) do |parent|
          Conversations::ValidateHistoricalAnchor.call(
            parent: parent,
            kind: "thread",
            historical_anchor_message_id: @historical_anchor_message_id,
            record: parent
          )

          conversation = Conversation.create!(
            installation: parent.installation,
            workspace: parent.workspace,
            execution_environment: parent.execution_environment,
            agent_deployment: parent.agent_deployment,
            parent_conversation: parent,
            kind: "thread",
            purpose: parent.purpose,
            lifecycle_state: "active",
            historical_anchor_message_id: @historical_anchor_message_id
          )

          initialize_child_conversation!(conversation: conversation, parent: parent)
        end
      end
    end
  end
end
