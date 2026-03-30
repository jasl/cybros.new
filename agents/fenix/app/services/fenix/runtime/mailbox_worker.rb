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
        return handle_agent_task_close! if agent_task_close_request?
        raise UnsupportedMailboxItemError, "unsupported mailbox item #{@mailbox_item.fetch("item_type", "execution_assignment")}" unless execution_assignment?

        runtime_execution = RuntimeExecution.find_by(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          attempt_no: @mailbox_item.fetch("attempt_no")
        )
        runtime_execution ||= create_runtime_execution!

        RuntimeExecutionJob.perform_later(runtime_execution.id) if runtime_execution.previously_new_record?
        runtime_execution
      end

      private

      def create_runtime_execution!
        RuntimeExecution.create!(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          protocol_message_id: @mailbox_item.fetch("protocol_message_id"),
          logical_work_id: @mailbox_item.fetch("logical_work_id"),
          attempt_no: @mailbox_item.fetch("attempt_no"),
          runtime_plane: @mailbox_item.fetch("runtime_plane"),
          mailbox_item_payload: @mailbox_item
        )
      rescue ActiveRecord::RecordNotUnique
        RuntimeExecution.find_by!(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          attempt_no: @mailbox_item.fetch("attempt_no")
        )
      end

      def execution_assignment?
        @mailbox_item.fetch("item_type", "execution_assignment") == "execution_assignment"
      end

      def agent_task_close_request?
        @mailbox_item.fetch("item_type", nil) == "resource_close_request" &&
          @mailbox_item.dig("payload", "resource_type") == "AgentTaskRun"
      end

      def handle_agent_task_close!
        agent_task_run_id = @mailbox_item.dig("payload", "resource_id")

        Fenix::Runtime::AttachedCommandSessionRegistry.terminate_for_agent_task(
          agent_task_run_id: agent_task_run_id
        )
        Fenix::Runtime::AttemptRegistry.release(agent_task_run_id: agent_task_run_id)

        :handled
      end
    end
  end
end
