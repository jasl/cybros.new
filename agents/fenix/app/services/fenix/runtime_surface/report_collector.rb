require "securerandom"

module Fenix
  module RuntimeSurface
    class ReportCollector
      def initialize(context:, on_report: nil)
        @context = context
        @on_report = on_report
        @reports = []
      end

      attr_reader :reports

      def started!(expected_duration_seconds: 30)
        append_report(base_report("execution_started").merge(
          "expected_duration_seconds" => expected_duration_seconds
        ))
      end

      def progress!(progress_payload:)
        append_report(base_report("execution_progress").merge(
          "progress_payload" => progress_payload
        ))
      end

      def complete!(terminal_payload:)
        append_report(base_report("execution_complete").merge(
          "terminal_payload" => terminal_payload
        ))
      end

      def fail!(terminal_payload:)
        append_report(base_report("execution_fail").merge(
          "terminal_payload" => terminal_payload
        ))
      end

      private

      def append_report(report)
        @reports << report
        @on_report&.call(report.deep_dup)
      end

      def base_report(method_id)
        {
          "method_id" => method_id,
          "protocol_message_id" => "fenix-#{method_id}-#{SecureRandom.uuid}",
          "control_plane" => @context.fetch("control_plane"),
          "mailbox_item_id" => @context.fetch("item_id"),
          "agent_task_run_id" => @context.fetch("agent_task_run_id"),
          "logical_work_id" => @context.fetch("logical_work_id"),
          "attempt_no" => @context.fetch("attempt_no"),
        }
      end
    end
  end
end
