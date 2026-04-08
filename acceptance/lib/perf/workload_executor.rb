# frozen_string_literal: true

module Acceptance
  module Perf
    class WorkloadExecutor
      def initialize(run_execution_assignment:, run_program_exchange:, append_event:, time_source: nil)
        @run_execution_assignment = run_execution_assignment
        @run_program_exchange = run_program_exchange
        @append_event = append_event
        @time_source = time_source || -> { Time.now }
      end

      def call(conversation:, registration:, task:, slot_index:, event_output_path:)
        started_at = current_time
        execution = execute_task(
          conversation:,
          registration:,
          task:,
          slot_index:
        )
        finished_at = current_time

        @append_event.call(
          path: event_output_path,
          payload: {
            "recorded_at" => finished_at.utc.iso8601(6),
            "source_app" => "acceptance",
            "instance_label" => registration.fetch("slot_label"),
            "event_name" => "benchmark.workload.item_completed",
            "workload_kind" => task.fetch("workload_kind"),
            "duration_ms" => ((finished_at - started_at) * 1000.0).round(3),
            "success" => workload_success?(execution),
            "conversation_public_id" => execution.fetch("conversation_public_id", conversation.fetch("public_id")),
            "turn_public_id" => execution["turn_public_id"],
            "workflow_run_public_id" => execution["workflow_run_public_id"],
            "agent_program_public_id" => extract_agent_program_public_id(registration),
          }
        )

        execution
      end

      private

      def execute_task(conversation:, registration:, task:, slot_index:)
        case task.fetch("workload_kind")
        when "execution_assignment"
          @run_execution_assignment.call(
            conversation:,
            registration:,
            task:,
            slot_index:
          )
        when "program_exchange_mock"
          @run_program_exchange.call(
            conversation:,
            registration:,
            task:,
            slot_index:
          )
        else
          raise ArgumentError, "unsupported workload kind: #{task.fetch("workload_kind")}"
        end
      end

      def workload_success?(execution)
        %w[completed ok].include?(execution.fetch("status"))
      end

      def extract_agent_program_public_id(registration)
        agent_program_version = registration.fetch("agent_program_version")
        return agent_program_version.agent_program.public_id if agent_program_version.respond_to?(:agent_program)

        agent_program_version.fetch("agent_program_public_id")
      end

      def current_time
        return @time_source.call if @time_source.respond_to?(:call)
        return @time_source.next if @time_source.respond_to?(:next)

        raise ArgumentError, "time_source must respond to call or next"
      end
    end
  end
end
