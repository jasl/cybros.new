module Fenix
  module Runtime
    class MailboxWorker
      class UnsupportedMailboxItemError < StandardError; end

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:)
        @mailbox_item = mailbox_item.deep_stringify_keys
      end

      def call
        raise UnsupportedMailboxItemError, "unsupported mailbox item #{@mailbox_item.fetch("item_type", "execution_assignment")}" unless execution_assignment?

        runtime_execution = RuntimeExecution.find_or_create_by!(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          attempt_no: @mailbox_item.fetch("attempt_no")
        ) do |execution|
          execution.protocol_message_id = @mailbox_item.fetch("protocol_message_id")
          execution.logical_work_id = @mailbox_item.fetch("logical_work_id")
          execution.runtime_plane = @mailbox_item.fetch("runtime_plane")
          execution.mailbox_item_payload = @mailbox_item
        end

        RuntimeExecutionJob.perform_later(runtime_execution.id) if runtime_execution.previously_new_record?
        runtime_execution
      end

      private

      def execution_assignment?
        @mailbox_item.fetch("item_type", "execution_assignment") == "execution_assignment"
      end
    end
  end
end
