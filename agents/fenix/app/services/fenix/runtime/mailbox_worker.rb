module Fenix
  module Runtime
    class MailboxWorker
      class UnsupportedMailboxItemError < StandardError; end

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, deliver_reports: false, control_client: nil, inline: false)
        @mailbox_item = mailbox_item.deep_stringify_keys
        @deliver_reports = deliver_reports
        @control_client = control_client
        @inline = inline
      end

      def call
        return handle_agent_task_close! if agent_task_close_request?
        return handle_process_run_close! if process_run_close_request?
        raise UnsupportedMailboxItemError, "unsupported mailbox item #{@mailbox_item.fetch("item_type", "execution_assignment")}" unless execution_assignment?

        runtime_execution = RuntimeExecution.find_by(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          attempt_no: @mailbox_item.fetch("attempt_no")
        )
        runtime_execution ||= create_runtime_execution!

        enqueue_or_run!(runtime_execution) if runtime_execution.previously_new_record?
        @inline ? runtime_execution.reload : runtime_execution
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

      def process_run_close_request?
        @mailbox_item.fetch("item_type", nil) == "resource_close_request" &&
          @mailbox_item.dig("payload", "resource_type") == "ProcessRun"
      end

      def handle_agent_task_close!
        agent_task_run_id = @mailbox_item.dig("payload", "resource_id")

        Fenix::Runtime::AttachedCommandSessionRegistry.terminate_for_agent_task(
          agent_task_run_id: agent_task_run_id
        )
        Fenix::Runtime::AttemptRegistry.release(agent_task_run_id: agent_task_run_id)
        report_close_lifecycle! if @deliver_reports

        :handled
      end

      def handle_process_run_close!
        Fenix::Processes::Manager.close!(
          mailbox_item: @mailbox_item,
          deliver_reports: @deliver_reports,
          control_client: @control_client
        )
      end

      def report_close_lifecycle!
        return if @control_client.blank?

        acknowledgment = base_close_report("resource_close_acknowledged")
        terminal = base_close_report("resource_closed").merge(
          "close_outcome_kind" => "graceful",
          "close_outcome_payload" => { "source" => "fenix_runtime" }
        )

        @control_client.report!(payload: acknowledgment)
        @control_client.report!(payload: terminal)
      end

      def enqueue_or_run!(runtime_execution)
        if @inline
          RuntimeExecutionJob.perform_now(runtime_execution.id, deliver_reports: @deliver_reports)
        else
          RuntimeExecutionJob.perform_later(runtime_execution.id, deliver_reports: @deliver_reports)
        end
      end

      def base_close_report(method_id)
        {
          "method_id" => method_id,
          "protocol_message_id" => "fenix-#{method_id}-#{SecureRandom.uuid}",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "close_request_id" => @mailbox_item.fetch("item_id"),
          "resource_type" => @mailbox_item.dig("payload", "resource_type"),
          "resource_id" => @mailbox_item.dig("payload", "resource_id"),
        }
      end
    end
  end
end
