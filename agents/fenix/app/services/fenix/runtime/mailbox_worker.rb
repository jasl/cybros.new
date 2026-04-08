module Fenix
  module Runtime
    class MailboxWorker
      class UnsupportedMailboxItemError < StandardError; end

      SQLITE_LOCK_RETRY_ATTEMPTS = 5
      SQLITE_LOCK_RETRY_DELAY_SECONDS = 0.05

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
        return handle_subagent_session_close! if subagent_session_close_request?
        raise UnsupportedMailboxItemError, "unsupported mailbox item #{@mailbox_item.fetch("item_type", "execution_assignment")}" unless executable_mailbox_item?

        runtime_execution = find_or_create_runtime_execution!

        dispatch_runtime_execution!(runtime_execution)
        @inline ? runtime_execution.reload : runtime_execution
      end

      private

      def find_or_create_runtime_execution!
        with_transient_sqlite_retry do
          RuntimeExecution.find_by(
            mailbox_item_id: @mailbox_item.fetch("item_id"),
            attempt_no: @mailbox_item.fetch("attempt_no")
          ) || create_runtime_execution!
        end
      end

      def create_runtime_execution!
        RuntimeExecution.create!(
          agent_task_run_id: @mailbox_item.dig("payload", "task", "agent_task_run_id"),
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          protocol_message_id: @mailbox_item.fetch("protocol_message_id"),
          logical_work_id: @mailbox_item.fetch("logical_work_id"),
          attempt_no: @mailbox_item.fetch("attempt_no"),
          control_plane: @mailbox_item.fetch("control_plane"),
          item_type: @mailbox_item.fetch("item_type", "execution_assignment"),
          request_kind: @mailbox_item.dig("payload", "request_kind").presence || @mailbox_item.fetch("item_type", "execution_assignment"),
          request_payload: @mailbox_item.fetch("payload")
        )
      rescue ActiveRecord::RecordNotUnique
        RuntimeExecution.find_by!(
          mailbox_item_id: @mailbox_item.fetch("item_id"),
          attempt_no: @mailbox_item.fetch("attempt_no")
        )
      end

      def dispatch_runtime_execution!(runtime_execution)
        return runtime_execution unless dispatch_runtime_execution?(runtime_execution)

        with_transient_sqlite_retry do
          runtime_execution.with_lock do
            runtime_execution.reload
            return runtime_execution unless dispatch_runtime_execution?(runtime_execution)

            enqueue_or_run!(runtime_execution)
            runtime_execution.update!(enqueued_at: Time.current) unless @inline
          end
        end

        runtime_execution
      end

      def dispatch_runtime_execution?(runtime_execution)
        return runtime_execution.queued? && runtime_execution.started_at.blank? && runtime_execution.finished_at.blank? if @inline

        runtime_execution.dispatchable?
      end

      def with_transient_sqlite_retry
        attempts = 0

        begin
          attempts += 1
          yield
        rescue ActiveRecord::StatementInvalid => error
          raise unless retryable_sqlite_lock_error?(error) && attempts < SQLITE_LOCK_RETRY_ATTEMPTS

          sleep(SQLITE_LOCK_RETRY_DELAY_SECONDS * attempts)
          retry
        end
      end

      def retryable_sqlite_lock_error?(error)
        details = [error.message, error.cause&.message, error.cause&.class&.name].compact.join(" ")

        details.match?(/database(?: table)? is locked|lockedexception|busyexception|sqlite_busy|sqlite_locked|database is busy/i)
      end

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
        agent_task_run_id = @mailbox_item.dig("payload", "resource_id")

        Fenix::Runtime::CommandRunRegistry.terminate_for_agent_task(
          agent_task_run_id: agent_task_run_id
        )
        cancel_runtime_executions!(agent_task_run_id:)
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

      def handle_subagent_session_close!
        report_close_lifecycle! if @deliver_reports

        :handled
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
          RuntimeExecutionJob
            .set(queue: Fenix::Runtime::ExecutionTopology.runtime_execution_queue_name(mailbox_item: runtime_execution.to_mailbox_item))
            .perform_later(runtime_execution.id, deliver_reports: @deliver_reports)
        end
      end

      def cancel_runtime_executions!(agent_task_run_id:)
        RuntimeExecution.active_for_agent_task(agent_task_run_id).find_each do |runtime_execution|
          runtime_execution.cancel!(
            request_kind: @mailbox_item.dig("payload", "request_kind"),
            reason_kind: @mailbox_item.dig("payload", "reason_kind"),
            occurred_at: Time.current
          )
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
