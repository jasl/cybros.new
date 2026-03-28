module Conversations
  module CreationSupport
    private

    def create_root_conversation!(workspace:, execution_environment:, agent_deployment:, purpose:)
      conversation = Conversation.create!(
        installation: workspace.installation,
        workspace: workspace,
        execution_environment: execution_environment,
        agent_deployment: agent_deployment,
        kind: "root",
        purpose: purpose,
        lifecycle_state: "active"
      )

      create_self_closure!(conversation)
      CanonicalStores::BootstrapForConversation.call(conversation: conversation)
      Conversations::RefreshRuntimeContract.call(conversation: conversation)

      conversation
    end

    def initialize_child_conversation!(conversation:, parent:)
      create_parent_closures!(conversation, parent:)
      create_canonical_store_reference_for!(conversation, parent:)
      Conversations::RefreshRuntimeContract.call(conversation: conversation)
      conversation
    end

    def build_child_conversation(parent:, kind:, historical_anchor_message_id: nil, addressability: "owner_addressable")
      Conversation.new(
        installation: parent.installation,
        workspace: parent.workspace,
        execution_environment: parent.execution_environment,
        agent_deployment: parent.agent_deployment,
        parent_conversation: parent,
        kind: kind,
        purpose: parent.purpose,
        addressability: addressability,
        lifecycle_state: "active",
        historical_anchor_message_id: historical_anchor_message_id
      )
    end

    def create_parent_closures!(conversation, parent:)
      ConversationClosure.where(descendant_conversation: parent).find_each do |closure|
        ConversationClosure.create!(
          installation: conversation.installation,
          ancestor_conversation: closure.ancestor_conversation,
          descendant_conversation: conversation,
          depth: closure.depth + 1
        )
      end

      create_self_closure!(conversation)
    end

    def create_self_closure!(conversation)
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
