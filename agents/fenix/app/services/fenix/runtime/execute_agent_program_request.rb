require "securerandom"

module Fenix
  module Runtime
    class ExecuteAgentProgramRequest
      Result = Struct.new(:status, :reports, :trace, :output, :error, keyword_init: true)

      UnsupportedRequestKindError = Class.new(StandardError)

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, on_report: nil, control_client: nil, cancellation_probe: nil)
        @mailbox_item = mailbox_item.deep_stringify_keys
        @on_report = on_report
        @control_client = control_client
        @cancellation_probe = cancellation_probe
        @reports = []
      end

      def call
        check_canceled!

        response_payload =
          case request_kind
          when "prepare_round"
            Fenix::Runtime::PrepareRound.call(payload: request_payload)
          when "execute_program_tool"
            execute_program_tool
          else
            raise UnsupportedRequestKindError, "unsupported agent program request #{request_kind}"
          end

        report = base_report("agent_program_completed").merge(
          "response_payload" => response_payload
        )
        append_report(report)

        Result.new(
          status: completed_response?(response_payload) ? "completed" : "failed",
          reports: @reports,
          trace: Array(response_payload["trace"]),
          output: completed_response?(response_payload) ? response_payload : nil,
          error: completed_response?(response_payload) ? nil : response_payload.fetch("error")
        )
      rescue StandardError => error
        error_payload = build_error_payload(error)
        report = base_report("agent_program_failed").merge(
          "error_payload" => error_payload
        )
        append_report(report)

        Result.new(
          status: "failed",
          reports: @reports,
          trace: [],
          error: error_payload
        )
      end

      private

      def execute_program_tool
        result = Fenix::Runtime::ExecuteProgramTool.call(
          payload: request_payload,
          control_client: @control_client,
          cancellation_probe: @cancellation_probe
        )

        return result if result.fetch("status") == "completed"

        raise ToolExecutionFailed.new(result.fetch("error"))
      end

      def append_report(report)
        @reports << report
        @on_report&.call(report.deep_dup)
        @control_client&.report!(payload: report)
      end

      def request_payload
        @request_payload ||= @mailbox_item.fetch("payload").deep_stringify_keys.except("request_kind")
      end

      def request_kind
        @request_kind ||= @mailbox_item.dig("payload", "request_kind").to_s
      end

      def base_report(method_id)
        {
          "method_id" => method_id,
          "protocol_message_id" => "fenix-#{method_id}-#{SecureRandom.uuid}",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "runtime_plane" => @mailbox_item.fetch("runtime_plane"),
          "request_kind" => request_kind,
          "workflow_node_id" => request_payload["workflow_node_id"],
          "conversation_id" => request_payload["conversation_id"],
          "turn_id" => request_payload["turn_id"],
        }.compact
      end

      def completed_response?(response_payload)
        return true unless request_kind == "execute_program_tool"

        response_payload.fetch("status") == "completed"
      end

      def build_error_payload(error)
        if error.is_a?(ToolExecutionFailed)
          error.error_payload
        elsif error.is_a?(UnsupportedRequestKindError)
          {
            "classification" => "semantic",
            "code" => "unsupported_request_kind",
            "message" => error.message,
            "retryable" => false,
          }
        else
          {
            "classification" => "runtime",
            "code" => "runtime_error",
            "message" => error.message,
            "retryable" => false,
          }
        end
      end

      def check_canceled!
        raise CancellationRequestedError, "execution canceled" if @cancellation_probe&.call
      end

      class CancellationRequestedError < StandardError; end

      class ToolExecutionFailed < StandardError
        attr_reader :error_payload

        def initialize(error_payload)
          @error_payload = error_payload.deep_stringify_keys
          super(@error_payload.fetch("message"))
        end
      end
    end
  end
end
