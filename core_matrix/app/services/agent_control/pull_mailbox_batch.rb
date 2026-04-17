module AgentControl
  class PullMailboxBatch
    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime_connection:, limit: Poll::DEFAULT_LIMIT)
      @execution_runtime_connection = execution_runtime_connection
      @limit = limit
    end

    def call
      {
        "method_id" => "execution_runtime_mailbox_pull",
        "mailbox_items" => SerializeMailboxItems.call(
          Poll.call(
            execution_runtime_connection: @execution_runtime_connection,
            limit: @limit
          )
        ),
      }
    end
  end
end
