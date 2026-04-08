require "securerandom"

module Fenix
  module Runtime
    class ExecuteMailboxItem
      UnsupportedMailboxItemError = Class.new(StandardError)

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, deliver_reports: false, control_client: nil)
        @mailbox_item = mailbox_item.deep_stringify_keys
        @deliver_reports = deliver_reports
        @control_client = control_client
      end

      def call
        case item_type
        when "execution_assignment"
          fail_execution_assignment!
        when "agent_program_request"
          execute_agent_program_request!
        else
          raise UnsupportedMailboxItemError, "unsupported mailbox item #{item_type.inspect}"
        end
      end

      private

      def fail_execution_assignment!
        error_payload = {
          "classification" => "runtime",
          "code" => "executor_tool_slice_not_ready",
          "message" => "executor tool slice is not implemented yet in this runtime build",
          "retryable" => false,
        }
        report = {
          "method_id" => "execution_fail",
          "protocol_message_id" => "fenix-execution_fail-#{SecureRandom.uuid}",
          "control_plane" => control_plane,
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "agent_task_run_id" => @mailbox_item.dig("payload", "task", "agent_task_run_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "terminal_payload" => error_payload,
        }.compact

        emit_result(report: report, error_payload: error_payload)
      end

      def execute_agent_program_request!
        response_payload = execute_agent_program_request

        return emit_agent_program_completion(response_payload) if response_payload.fetch("status") == "ok"

        emit_agent_program_failure(response_payload.fetch("failure"))
      rescue StandardError => error
        emit_agent_program_failure(runtime_error_payload_for(error))
      end

      def execute_agent_program_request
        case request_kind
        when "prepare_round"
          Fenix::Runtime::PrepareRound.call(payload: mailbox_payload)
        when "execute_program_tool"
          Fenix::Runtime::ExecuteProgramTool.call(payload: mailbox_payload)
        else
          raise UnsupportedMailboxItemError, "unsupported agent program request #{request_kind.inspect}"
        end
      end

      def emit_agent_program_completion(response_payload)
        report = {
          "method_id" => "agent_program_completed",
          "protocol_message_id" => "fenix-agent_program_completed-#{SecureRandom.uuid}",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "control_plane" => control_plane,
          "request_kind" => request_kind,
          "workflow_node_id" => mailbox_payload.dig("task", "workflow_node_id"),
          "conversation_id" => mailbox_payload.dig("task", "conversation_id"),
          "turn_id" => mailbox_payload.dig("task", "turn_id"),
          "response_payload" => response_payload,
        }.compact

        @control_client&.report!(payload: report) if @deliver_reports

        {
          "status" => "ok",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "reports" => [report],
          "response" => response_payload,
        }
      end

      def emit_agent_program_failure(error_payload)
        report = {
          "method_id" => "agent_program_failed",
          "protocol_message_id" => "fenix-agent_program_failed-#{SecureRandom.uuid}",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "control_plane" => control_plane,
          "request_kind" => request_kind,
          "workflow_node_id" => mailbox_payload.dig("task", "workflow_node_id"),
          "conversation_id" => mailbox_payload.dig("task", "conversation_id"),
          "turn_id" => mailbox_payload.dig("task", "turn_id"),
          "error_payload" => error_payload,
        }.compact

        emit_result(report: report, error_payload: error_payload)
      end

      def emit_result(report:, error_payload:)
        @control_client&.report!(payload: report) if @deliver_reports

        {
          "status" => "failed",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "reports" => [report],
          "error" => error_payload,
        }
      end

      def item_type
        @mailbox_item.fetch("item_type", "execution_assignment")
      end

      def request_kind
        mailbox_payload.fetch("request_kind")
      end

      def mailbox_payload
        @mailbox_payload ||= @mailbox_item.fetch("payload", {}).deep_stringify_keys
      end

      def control_plane
        @mailbox_item.fetch("control_plane")
      end

      def runtime_error_payload_for(error)
        {
          "classification" => "runtime",
          "code" => "program_request_failed",
          "message" => error.message,
          "retryable" => false,
        }
      end
    end
  end
end
