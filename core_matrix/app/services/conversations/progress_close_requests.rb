module Conversations
  class ProgressCloseRequests
    CLOSE_PENDING_STATES = %w[requested acknowledged].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current)
      @conversation = conversation
      @occurred_at = occurred_at
    end

    def call
      pending_resources.each do |resource|
        mailbox_item = open_close_request_for(resource)
        next if mailbox_item.blank?

        AgentControl::ProgressCloseRequest.call(
          mailbox_item: mailbox_item,
          occurred_at: @occurred_at
        )
      end
    end

    private

    def pending_resources
      EnumeratorChain.new(
        AgentTaskRun.where(conversation: @conversation, close_state: CLOSE_PENDING_STATES),
        ProcessRun.where(conversation: @conversation, close_state: CLOSE_PENDING_STATES),
        SubagentRun.joins(:workflow_run)
          .where(workflow_runs: { conversation_id: @conversation.id }, close_state: CLOSE_PENDING_STATES)
      )
    end

    def open_close_request_for(resource)
      AgentControlMailboxItem
        .where(
          installation_id: @conversation.installation_id,
          item_type: "resource_close_request",
          status: AgentControl::ProgressCloseRequest::ACTIVE_STATUSES
        )
        .where("payload ->> 'resource_type' = ? AND payload ->> 'resource_id' = ?", resource.class.name, resource.public_id)
        .order(id: :desc)
        .first
    end

    class EnumeratorChain
      include Enumerable

      def initialize(*relations)
        @relations = relations
      end

      def each
        @relations.each do |relation|
          relation.find_each do |record|
            yield record
          end
        end
      end
    end
  end
end
