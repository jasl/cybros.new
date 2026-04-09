require "securerandom"

module Fenix
  module Runtime
    class MailboxWorker
      class UnsupportedMailboxItemError < StandardError; end

      QueuedMailboxExecution = Struct.new(
        :mailbox_item_id,
        :logical_work_id,
        :attempt_no,
        :control_plane,
        :status,
        keyword_init: true
      )

      def self.call(...)
        new(...).call
      end

      def self.execution_event_payload(mailbox_item)
        mailbox_item = mailbox_item.deep_stringify_keys
        task_payload = mailbox_item.fetch("payload", {})
        runtime_context = task_payload.fetch("runtime_context", {})
        task = task_payload.fetch("task", {})

        {
          "mailbox_item_public_id" => mailbox_item["item_id"],
          "control_plane" => mailbox_item["control_plane"],
          "item_type" => mailbox_item.fetch("item_type", "execution_assignment"),
          "agent_program_public_id" => runtime_context["agent_program_id"],
          "user_public_id" => runtime_context["user_id"],
          "conversation_public_id" => task["conversation_id"],
          "turn_public_id" => task["turn_id"],
          "workflow_node_public_id" => task["workflow_node_id"],
        }.compact
      end

      def self.instrument_execution(mailbox_item:, notifier: ActiveSupport::Notifications)
        payload = execution_event_payload(mailbox_item).merge(
          "success" => false
        )

        notifier.instrument("perf.runtime.mailbox_execution", payload) do
          result = yield
          payload["success"] = true
          apply_execution_result!(payload, result)
          result
        end
      rescue StandardError => error
        payload["metadata"] = {
          "error_class" => error.class.name,
          "message" => error.message,
        }
        raise
      end

      def self.apply_execution_result!(payload, result)
        metadata = {}

        if result.respond_to?(:status)
          metadata["execution_status"] = result.status
        elsif result.is_a?(Hash)
          metadata["execution_status"] = result["status"] || result[:status]
        elsif result.is_a?(Symbol)
          metadata["execution_status"] = result.to_s
        end

        payload["metadata"] = metadata if metadata.present?
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
        return handle_subagent_session_close! if subagent_session_close_request?

        raise UnsupportedMailboxItemError, "unsupported mailbox item #{@mailbox_item.fetch("item_type", "execution_assignment")}" unless executable_mailbox_item?

        @inline ? execute_inline! : enqueue_execution!
      end

      private

      def execution_assignment?
        @mailbox_item.fetch("item_type", "execution_assignment") == "execution_assignment"
      end

      def agent_program_request?
        @mailbox_item.fetch("item_type", nil) == "agent_program_request"
      end

      def executable_mailbox_item?
        execution_assignment? || agent_program_request?
      end

      def agent_task_close_request?
        @mailbox_item.fetch("item_type", nil) == "resource_close_request" &&
          @mailbox_item.dig("payload", "resource_type") == "AgentTaskRun"
      end

      def process_run_close_request?
        @mailbox_item.fetch("item_type", nil) == "resource_close_request" &&
          @mailbox_item.dig("payload", "resource_type") == "ProcessRun"
      end

      def subagent_session_close_request?
        @mailbox_item.fetch("item_type", nil) == "resource_close_request" &&
          @mailbox_item.dig("payload", "resource_type") == "SubagentSession"
      end

      def handle_agent_task_close!
        self.class.instrument_execution(mailbox_item: @mailbox_item) do
          report_close_lifecycle! if @deliver_reports
          :handled
        end
      end

      def handle_process_run_close!
        self.class.instrument_execution(mailbox_item: @mailbox_item) do
          if defined?(Fenix::Processes::Manager)
            Fenix::Processes::Manager.close!(
              mailbox_item: @mailbox_item,
              deliver_reports: @deliver_reports,
              control_client: resolved_control_client_if_needed
            )
          else
            report_close_failure!("local process manager is not available")
            :unsupported
          end
        end
      end

      def handle_subagent_session_close!
        self.class.instrument_execution(mailbox_item: @mailbox_item) do
          report_close_lifecycle! if @deliver_reports
          :handled
        end
      end

      def execute_inline!
        self.class.instrument_execution(mailbox_item: @mailbox_item) do
          Fenix::Runtime::ExecuteMailboxItem.call(
            mailbox_item: @mailbox_item,
            deliver_reports: @deliver_reports,
            control_client: resolved_control_client_if_needed
          )
        end
      end

      def enqueue_execution!
        Fenix::Runtime::MailboxExecutionJob.perform_later(
          @mailbox_item,
          deliver_reports: @deliver_reports,
          enqueued_at_iso8601: Time.current.iso8601(6),
          queue_name: Fenix::Runtime::MailboxExecutionJob.queue_name,
          control_plane_context: serialized_control_plane_context
        )

        QueuedMailboxExecution.new(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          logical_work_id: @mailbox_item.fetch("logical_work_id"),
          attempt_no: @mailbox_item.fetch("attempt_no"),
          control_plane: @mailbox_item.fetch("control_plane"),
          status: "queued"
        )
      end

      def report_close_lifecycle!
        client = resolved_control_client_if_needed
        return if client.blank?

        acknowledgment = base_close_report("resource_close_acknowledged")
        terminal = base_close_report("resource_closed").merge(
          "close_outcome_kind" => "graceful",
          "close_outcome_payload" => { "source" => "fenix_runtime" }
        )

        client.report!(payload: acknowledgment)
        client.report!(payload: terminal)
      end

      def report_close_failure!(message)
        client = resolved_control_client_if_needed
        return if client.blank?

        client.report!(
          payload: base_close_report("resource_close_failed").merge(
            "close_outcome_kind" => "unsupported",
            "close_outcome_payload" => { "message" => message }
          )
        )
      end

      def resolved_control_client_if_needed
        return @control_client if @control_client.present?
        return nil unless @deliver_reports

        @control_client = Fenix::Runtime::ControlPlane.client
      end

      def serialized_control_plane_context
        return nil unless @deliver_reports

        client = resolved_control_client_if_needed
        return nil unless client.respond_to?(:connection_context)

        client.connection_context.deep_stringify_keys
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
