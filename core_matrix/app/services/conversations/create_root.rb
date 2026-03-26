module Conversations
  class CreateRoot
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, execution_environment:, agent_deployment:)
      @workspace = workspace
      @execution_environment = execution_environment
      @agent_deployment = agent_deployment
    end

    def call
      ApplicationRecord.transaction do
        conversation = Conversation.create!(
          installation: @workspace.installation,
          workspace: @workspace,
          execution_environment: @execution_environment,
          agent_deployment: @agent_deployment,
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

        CanonicalStores::BootstrapForConversation.call(conversation: conversation)

        conversation
      end
    end
  end
end
