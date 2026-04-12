# frozen_string_literal: true

module Acceptance
  module Perf
    # Executes one benchmark workload item and emits its completion event.
    class WorkloadExecutor
      def initialize(run_execution_assignment:, run_agent_request_exchange:, append_event:, time_source: nil)
        @run_execution_assignment = run_execution_assignment
        @run_agent_request_exchange = run_agent_request_exchange
        @append_event = append_event
        @time_source = time_source || -> { Time.zone.now }
      end

      # rubocop:disable Metrics/MethodLength
      def call(conversation:, registration:, task:, slot_index:, event_output_path:)
        started_at = current_time
        execution = execute_task(
          conversation:,
          registration:,
          task:,
          slot_index:
        )
        finished_at = current_time

        append_completion_event(
          event_output_path: event_output_path,
          conversation: conversation,
          registration: registration,
          task: task,
          execution: execution,
          started_at: started_at,
          finished_at: finished_at
        )

        execution
      end
      # rubocop:enable Metrics/MethodLength

      private

      def execute_task(conversation:, registration:, task:, slot_index:)
        runner_for(task).call(
          conversation:,
          registration:,
          task:,
          slot_index:
        )
      end

      def runner_for(task)
        case task.fetch('workload_kind')
        when 'execution_assignment' then @run_execution_assignment
        when 'agent_request_exchange_mock' then @run_agent_request_exchange
        else
          raise ArgumentError, "unsupported workload kind: #{task.fetch('workload_kind')}"
        end
      end

      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      def append_completion_event(
        event_output_path:,
        conversation:,
        registration:,
        task:,
        execution:,
        started_at:,
        finished_at:
      )
        @append_event.call(
          path: event_output_path,
          payload: completion_event_payload(
            conversation: conversation,
            registration: registration,
            task: task,
            execution: execution,
            started_at: started_at,
            finished_at: finished_at
          )
        )
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      def completion_event_payload(conversation:, registration:, task:, execution:, started_at:, finished_at:)
        {
          'recorded_at' => finished_at.utc.iso8601(6),
          'source_app' => 'acceptance',
          'instance_label' => registration.slot_label,
          'event_name' => 'benchmark.workload.item_completed',
          'workload_kind' => task.fetch('workload_kind'),
          'duration_ms' => ((finished_at - started_at) * 1000.0).round(3),
          'success' => workload_success?(execution),
          'conversation_public_id' => execution.fetch(
            'conversation_public_id',
            conversation_public_id_for(conversation)
          ),
          'turn_public_id' => execution['turn_public_id'],
          'workflow_run_public_id' => execution['workflow_run_public_id'],
          'agent_public_id' => extract_agent_public_id(registration)
        }
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      def workload_success?(execution)
        %w[completed ok].include?(execution.fetch('status'))
      end

      def extract_agent_public_id(registration)
        agent_definition_version = registration.agent_definition_version
        return agent_definition_version.agent.public_id if agent_definition_version.respond_to?(:agent)

        agent_definition_version.fetch('agent_public_id')
      end

      def conversation_public_id_for(conversation)
        return conversation.public_id if conversation.respond_to?(:public_id)

        conversation.fetch('public_id')
      end

      def current_time
        return @time_source.call if @time_source.respond_to?(:call)
        return @time_source.next if @time_source.respond_to?(:next)

        raise ArgumentError, 'time_source must respond to call or next'
      end
    end
  end
end
