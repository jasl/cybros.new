module AgentControl
  class SerializeMailboxItems
    def self.call(mailbox_items)
      new(mailbox_items:).call
    end

    def initialize(mailbox_items:)
      @mailbox_items = Array(mailbox_items).compact
    end

    def call
      return [] if @mailbox_items.empty?

      preload_associations!
      snapshot_cache = execution_snapshot_cache

      @mailbox_items.map do |mailbox_item|
        SerializeMailboxItem.call(mailbox_item, execution_snapshot_cache: snapshot_cache)
      end
    end

    private

    def preload_associations!
      ActiveRecord::Associations::Preloader.new(
        records: @mailbox_items,
        associations: [
          :payload_document,
          { agent_task_run: [:workflow_run, :workflow_node, :conversation, :turn] },
          { workflow_node: [:workflow_run, :conversation, :turn] },
          {
            execution_contract: [
              :agent_program_version,
              :execution_context_snapshot,
              :execution_capability_snapshot,
              { turn: [:conversation, :agent_program_version, :executor_program, :selected_input_message, :selected_output_message] },
            ],
          },
        ]
      ).call
    end

    def execution_snapshot_cache
      turns_by_id = {}

      @mailbox_items.each do |mailbox_item|
        turn =
          if mailbox_item.execution_assignment?
            mailbox_item.agent_task_run&.turn
          elsif mailbox_item.agent_program_request?
            mailbox_item.execution_contract&.turn
          end
        next if turn.blank? || turns_by_id.key?(turn.id)

        turns_by_id[turn.id] = turn
      end

      turns_by_id.transform_values(&:execution_snapshot)
    end
  end
end
