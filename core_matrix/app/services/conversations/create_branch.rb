module Conversations
  class CreateBranch
    include Conversations::RetentionGuard

    def self.call(...)
      new(...).call
    end

    def initialize(parent:, historical_anchor_message_id: nil)
      @parent = parent
      @historical_anchor_message_id = historical_anchor_message_id
    end

    def call
      ensure_conversation_retained!(@parent, message: "must be retained before branching")

      ApplicationRecord.transaction do
        conversation = Conversation.create!(
          installation: @parent.installation,
          workspace: @parent.workspace,
          execution_environment: @parent.execution_environment,
          agent_deployment: @parent.agent_deployment,
          parent_conversation: @parent,
          kind: "branch",
          purpose: @parent.purpose,
          lifecycle_state: "active",
          historical_anchor_message_id: @historical_anchor_message_id
        )

        create_closures_for!(conversation)
        create_canonical_store_reference_for!(conversation)
        create_branch_prefix_import_for!(conversation)
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

    def create_branch_prefix_import_for!(conversation)
      anchor_message = Message.find_by(
        id: @historical_anchor_message_id,
        installation_id: @parent.installation_id
      )
      return if anchor_message.blank?

      Conversations::AddImport.call(
        conversation: conversation,
        kind: "branch_prefix",
        source_conversation: @parent,
        source_message: anchor_message
      )
    end

    def create_canonical_store_reference_for!(conversation)
      parent_reference = @parent.canonical_store_reference ||
        raise(ActiveRecord::RecordNotFound, "canonical store reference is missing")

      CanonicalStoreReference.create!(
        owner: conversation,
        canonical_store_snapshot: parent_reference.canonical_store_snapshot
      )
    end
  end
end
