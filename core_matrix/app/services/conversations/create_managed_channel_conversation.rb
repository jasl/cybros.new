module Conversations
  class CreateManagedChannelConversation
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(workspace_agent: nil, source_conversation: nil, execution_runtime: nil, platform: nil, peer_kind: nil, peer_id: nil, session_metadata: {})
      @workspace_agent = workspace_agent
      @source_conversation = source_conversation
      @execution_runtime = execution_runtime
      @platform = platform
      @peer_kind = peer_kind
      @peer_id = peer_id
      @session_metadata = session_metadata
    end

    def call
      ApplicationRecord.transaction do
        return create_from_source_conversation! if @source_conversation.present?

        conversation = create_root_conversation!(
          workspace_agent: resolved_workspace_agent,
          workspace: resolved_workspace,
          agent: resolved_agent,
          purpose: "interactive",
          execution_runtime: resolved_execution_runtime,
          entry_policy_payload: managed_entry_policy_payload(
            workspace_agent: resolved_workspace_agent,
            purpose: "interactive"
          )
        )

        apply_managed_title!(conversation)
      end
    end

    private

    def create_from_source_conversation!
      conversation = build_child_conversation(
        parent: @source_conversation,
        kind: "fork",
        entry_policy_payload: managed_entry_policy_payload(
          workspace_agent: @source_conversation.workspace_agent,
          purpose: @source_conversation.purpose
        )
      )

      refresh_child_conversation_from_parent!(conversation: conversation, parent: @source_conversation)
      conversation.entry_policy_payload = managed_entry_policy_payload(
        workspace_agent: @source_conversation.workspace_agent,
        purpose: @source_conversation.purpose
      )
      assign_managed_title!(conversation)
      conversation.save!
      initialize_child_conversation!(conversation: conversation, parent: @source_conversation)
    end

    def managed_entry_policy_payload(workspace_agent:, purpose:)
      Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: workspace_agent.entry_policy_payload,
        purpose: purpose
      )
    end

    def resolved_workspace_agent
      @resolved_workspace_agent ||= @workspace_agent || raise(ArgumentError, "workspace_agent or source_conversation is required")
    end

    def resolved_workspace
      resolved_workspace_agent.workspace
    end

    def resolved_agent
      resolved_workspace_agent.agent
    end

    def resolved_execution_runtime
      @execution_runtime || resolved_workspace_agent.default_execution_runtime || resolved_agent.default_execution_runtime
    end

    def apply_managed_title!(conversation)
      title = managed_title
      return conversation if title.blank?

      conversation.update!(
        title: title,
        title_source: "agent",
        title_updated_at: Time.current
      )
      conversation
    end

    def assign_managed_title!(conversation)
      title = managed_title
      return conversation if title.blank?

      conversation.title = title
      conversation.title_source = "agent"
      conversation.title_updated_at = Time.current
      conversation
    end

    def managed_title
      @managed_title ||= Conversations::Metadata::BuildManagedChannelTitle.call(
        platform: @platform,
        peer_kind: @peer_kind,
        peer_id: @peer_id,
        session_metadata: @session_metadata
      )
    end
  end
end
