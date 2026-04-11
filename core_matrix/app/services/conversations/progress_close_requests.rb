module Conversations
  class ProgressCloseRequests
    CLOSE_PENDING_STATES = %w[requested acknowledged].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current, owned_subagent_connection_ids: nil)
      @conversation = conversation
      @occurred_at = occurred_at
      @owned_subagent_connection_ids = owned_subagent_connection_ids
    end

    def call
      pending_resource_groups.each do |resources|
        next if resources.empty?

        mailbox_items_by_resource_id = open_close_requests_for(
          resource_type: resources.first.class.name,
          resource_public_ids: resources.map(&:public_id)
        )

        resources.each do |resource|
          mailbox_item = mailbox_items_by_resource_id[resource.public_id]
          next if mailbox_item.blank?

          AgentControl::ProgressCloseRequest.call(
            mailbox_item: mailbox_item,
            resource: resource,
            occurred_at: @occurred_at
          )
        end
      end
    end

    private

    def pending_resource_groups
      [
        AgentTaskRun.where(conversation: @conversation, close_state: CLOSE_PENDING_STATES).to_a,
        ProcessRun.where(conversation: @conversation, close_state: CLOSE_PENDING_STATES).to_a,
        pending_subagent_connections,
      ]
    end

    def pending_subagent_connections
      SubagentConnection
        .where(id: owned_subagent_connection_ids, close_state: CLOSE_PENDING_STATES)
        .to_a
    end

    def owned_subagent_connection_ids
      @owned_subagent_connection_ids ||= SubagentConnections::OwnedTree.connection_ids_for(owner_conversation: @conversation)
    end

    def open_close_requests_for(resource_type:, resource_public_ids:)
      AgentControlMailboxItem
        .where(
          installation_id: @conversation.installation_id,
          item_type: "resource_close_request",
          status: AgentControl::ProgressCloseRequest::ACTIVE_STATUSES
        )
        .where("payload ->> 'resource_type' = ? AND payload ->> 'resource_id' IN (?)", resource_type, resource_public_ids)
        .order(id: :desc)
        .each_with_object({}) do |mailbox_item, index|
          resource_id = mailbox_item.payload["resource_id"]
          index[resource_id] ||= mailbox_item
        end
    end
  end
end
