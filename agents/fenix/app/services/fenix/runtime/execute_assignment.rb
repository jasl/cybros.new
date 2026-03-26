module Fenix
  module Runtime
    class ExecuteAssignment
      Result = Struct.new(:status, :reports, :trace, :output, :error, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:)
        @context = Fenix::Context::BuildExecutionContext.call(mailbox_item: mailbox_item)
        @collector = Fenix::RuntimeSurface::ReportCollector.new(context: @context)
        @trace = []
      end

      def call
        return fail_unsupported_runtime_plane unless @context.fetch("runtime_plane") == "agent"

        @collector.started!

        prepared = Fenix::Hooks::PrepareTurn.call(context: @context)
        @trace << prepared.fetch("trace")

        compacted = Fenix::Hooks::CompactContext.call(
          messages: prepared.fetch("messages"),
          budget_hints: @context.fetch("budget_hints"),
          likely_model: prepared.fetch("likely_model")
        )
        @trace << compacted.fetch("trace")

        case @context.dig("task_payload", "mode")
        when "raise_error"
          raise StandardError, "boom"
        else
          execute_deterministic_tool_flow
        end
      rescue StandardError => error
        handled_error = Fenix::Hooks::HandleError.call(
          error: error,
          logical_work_id: @context.fetch("logical_work_id"),
          attempt_no: @context.fetch("attempt_no")
        )
        @trace << { "hook" => "handle_error", "error" => handled_error.fetch("last_error_summary") }
        @collector.fail!(terminal_payload: handled_error)

        Result.new(
          status: "failed",
          reports: @collector.reports,
          trace: @trace,
          error: handled_error
        )
      end

      private

      def execute_deterministic_tool_flow
        expression = @context.dig("task_payload", "expression") || "2 + 2"
        tool_call = {
          "tool_name" => "calculator",
          "arguments" => { "expression" => expression },
        }
        reviewed_tool_call = Fenix::Hooks::ReviewToolCall.call(tool_call: tool_call)
        @trace << { "hook" => "review_tool_call", "tool_name" => reviewed_tool_call.fetch("tool_name") }

        @collector.progress!(progress_payload: { "stage" => "tool_reviewed" })

        tool_result = evaluate_expression(reviewed_tool_call.dig("arguments", "expression"))
        projected_result = Fenix::Hooks::ProjectToolResult.call(
          tool_call: reviewed_tool_call,
          tool_result: tool_result
        )
        @trace << { "hook" => "project_tool_result", "content" => projected_result.fetch("content") }

        finalized_output = Fenix::Hooks::FinalizeOutput.call(
          projected_result: projected_result,
          context: @context
        )
        @trace << { "hook" => "finalize_output", "output" => finalized_output.fetch("output") }

        @collector.complete!(terminal_payload: { "output" => finalized_output.fetch("output") })

        Result.new(
          status: "completed",
          reports: @collector.reports,
          trace: @trace,
          output: finalized_output.fetch("output")
        )
      end

      def evaluate_expression(expression)
        left, operator, right = expression.to_s.strip.split(/\s+/, 3)
        left_value = Integer(left)
        right_value = Integer(right)

        case operator
        when "+"
          left_value + right_value
        when "-"
          left_value - right_value
        else
          raise ArgumentError, "unsupported calculator operator #{operator}"
        end
      end

      def fail_unsupported_runtime_plane
        failure_payload = {
          "failure_kind" => "unsupported_runtime_plane",
          "last_error_summary" => "agent execution received #{@context.fetch("runtime_plane")} plane work",
          "retryable" => false,
        }
        @collector.fail!(terminal_payload: failure_payload)

        Result.new(
          status: "failed",
          reports: @collector.reports,
          trace: @trace,
          error: failure_payload
        )
      end
    end
  end
end
