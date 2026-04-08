# frozen_string_literal: true

module Acceptance
  module Perf
    # Drives one benchmark run across all runtime registrations and conversations.
    # rubocop:disable Metrics/ClassLength
    class WorkloadDriver
      BENCHMARK_MODE = 'multi_fenix_core_matrix_load'

      def self.call(...)
        new(...).call
      end

      def initialize(manifest:, registration_matrix:, create_conversation:, execute_workload_item:)
        @manifest = manifest
        @registration_matrix = registration_matrix
        @create_conversation = create_conversation
        @execute_workload_item = execute_workload_item
      end

      def call
        failures = structural_failures
        return structural_failure_report(failures) if failures.any?

        baseline_report(execute_assignments(build_assignments))
      end

      private

      def baseline_report(results)
        flattened_results = Array(results).flatten

        {
          'benchmark_mode' => BENCHMARK_MODE,
          'outcome' => { 'classification' => 'descriptive_baseline' },
          'structural_failures' => [],
          'completed_workload_items' => flattened_results.count,
          'runtime_assignments' => serialize_runtime_assignments,
          'workload_results' => flattened_results.map { |result| serialize_workload_result(result) },
          'bottleneck_hints' => []
        }
      end

      def structural_failures
        @registration_matrix.fetch('runtime_registrations').filter_map do |registration|
          next if registration.fetch('boot_status', 'ready') == 'ready'

          "#{registration.fetch('slot_label')} failed to boot: #{registration.fetch('boot_error',
                                                                                    'unknown boot failure')}"
        end
      end

      def structural_failure_report(failures)
        {
          'benchmark_mode' => BENCHMARK_MODE,
          'outcome' => { 'classification' => 'structural_failure' },
          'structural_failures' => failures,
          'completed_workload_items' => 0,
          'runtime_assignments' => serialize_runtime_assignments,
          'workload_results' => [],
          'bottleneck_hints' => []
        }
      end

      def build_assignments
        tasks = Array(@manifest.request_corpus)
        runtime_registrations = @registration_matrix.fetch('runtime_registrations')

        Array.new(@manifest.conversation_count) do |index|
          build_assignment(
            index: index,
            tasks: tasks,
            runtime_registrations: runtime_registrations
          )
        end
      end

      # rubocop:disable Metrics/MethodLength
      def execute_assignments(assignments)
        results = Array.new(assignments.length)
        failures = []
        failure_mutex = Mutex.new

        threads = assignments.each_with_index.map do |assignment, index|
          spawn_assignment_thread(
            assignment: assignment,
            index: index,
            results: results,
            failures: failures,
            failure_mutex: failure_mutex
          )
        end

        threads.each(&:join)
        raise failures.first if failures.any?

        results
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      def execute_assignment(assignment)
        conversation = create_conversation_for(assignment)
        shared_conversation = conversation.fetch(:conversation, conversation.fetch('conversation', conversation))

        assignment.fetch('tasks').each_with_index.map do |task, task_index|
          build_task_result(
            assignment: assignment,
            conversation: conversation,
            shared_conversation: shared_conversation,
            task: task,
            task_index: task_index
          )
        end
      end
      # rubocop:enable Metrics/MethodLength

      def build_task_sequence(tasks, assignment_index)
        Array.new(@manifest.turns_per_conversation) do |task_index|
          tasks.fetch((assignment_index + task_index) % tasks.length)
        end
      end

      def build_assignment(index:, tasks:, runtime_registrations:)
        registration = runtime_registrations.fetch(index % runtime_registrations.length)

        {
          'slot_index' => index + 1,
          'slot_label' => registration.fetch('slot_label'),
          'tasks' => build_task_sequence(tasks, index),
          'registration' => registration
        }
      end

      def spawn_assignment_thread(assignment:, index:, results:, failures:, failure_mutex:)
        Thread.new do
          results[index] = execute_assignment(assignment)
        rescue StandardError => e
          failure_mutex.synchronize { failures << e }
        ensure
          clear_active_database_connections!
        end
      end

      def create_conversation_for(assignment)
        with_database_connection do
          @create_conversation.call(
            agent_program_version: assignment.fetch('registration').fetch('agent_program_version')
          )
        end
      end

      # rubocop:disable Metrics/MethodLength
      def build_task_result(assignment:, conversation:, shared_conversation:, task:, task_index:)
        execution = with_database_connection do
          @execute_workload_item.call(
            conversation: shared_conversation,
            registration: assignment.fetch('registration'),
            task: task,
            slot_index: assignment.fetch('slot_index')
          )
        end

        assignment.merge(
          'conversation' => conversation,
          'task' => task,
          'task_sequence' => task_index + 1,
          'execution' => execution
        )
      end
      # rubocop:enable Metrics/MethodLength

      def with_database_connection(&block)
        return yield unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection_pool.with_connection(&block)
      ensure
        clear_active_database_connections!
      end

      def clear_active_database_connections!
        return unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection_handler.clear_active_connections!
      end

      def serialize_runtime_assignments
        @registration_matrix.fetch('runtime_registrations').map do |registration|
          registration.slice('slot_label', 'runtime_base_url', 'event_output_path', 'boot_status')
        end
      end

      def serialize_workload_result(result)
        {
          'slot_index' => result.fetch('slot_index'),
          'slot_label' => result.fetch('slot_label'),
          'event_output_path' => result.fetch('registration').fetch('event_output_path'),
          'task_sequence' => result.fetch('task_sequence'),
          'task' => result.fetch('task'),
          'execution' => result.fetch('execution')
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
