module Conversations
  module CreationSupport
    private

    def create_root_conversation!(workspace:, agent:, purpose:, execution_runtime: nil)
      capability_projection = WorkspacePolicies::Capabilities.projection_attributes_for(workspace: workspace)

      conversation = Conversation.create!(
        installation: workspace.installation,
        user: workspace.user,
        workspace: workspace,
        agent: agent,
        current_execution_runtime: execution_runtime,
        kind: "root",
        purpose: purpose,
        lifecycle_state: "active",
        **capability_projection
      )

      create_self_closure!(conversation)
      conversation.refresh_latest_anchors!(activity_at: conversation.created_at)

      conversation
    end

    def initialize_child_conversation!(conversation:, parent:)
      create_parent_closures!(conversation, parent:)
      create_lineage_store_reference_for!(conversation, parent:)
      conversation
    end

    def build_child_conversation(parent:, kind:, historical_anchor_message_id: nil, addressability: "owner_addressable")
      Conversation.new(
        installation: parent.installation,
        user: parent.user,
        workspace: parent.workspace,
        agent: parent.agent,
        current_execution_runtime: parent.current_execution_runtime,
        parent_conversation: parent,
        kind: kind,
        purpose: parent.purpose,
        addressability: addressability,
        lifecycle_state: "active",
        historical_anchor_message_id: historical_anchor_message_id,
        supervision_enabled: parent.supervision_enabled?,
        detailed_progress_enabled: parent.detailed_progress_enabled?,
        side_chat_enabled: parent.side_chat_enabled?,
        control_enabled: parent.control_enabled?
      )
    end

    def refresh_child_conversation_from_parent!(conversation:, parent:)
      conversation.installation = parent.installation
      conversation.user = parent.user
      conversation.workspace = parent.workspace
      conversation.agent = parent.agent
      conversation.current_execution_runtime = parent.current_execution_runtime
      conversation.parent_conversation = parent
      conversation.purpose = parent.purpose
      conversation.lifecycle_state = "active"
      conversation.supervision_enabled = parent.supervision_enabled?
      conversation.detailed_progress_enabled = parent.detailed_progress_enabled?
      conversation.side_chat_enabled = parent.side_chat_enabled?
      conversation.control_enabled = parent.control_enabled?
      conversation
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

    def create_lineage_store_reference_for!(conversation, parent:)
      parent_reference = parent.lineage_store_reference
      return if parent_reference.blank?

      LineageStoreReference.create!(
        owner: conversation,
        lineage_store_snapshot: parent_reference.lineage_store_snapshot
      )
    end
  end
end
