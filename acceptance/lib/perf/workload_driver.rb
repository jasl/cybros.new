# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize
module Acceptance
  module Perf
    # Drives one benchmark run across runtime registrations and conversations.
    class WorkloadDriver
      BENCHMARK_MODE = 'multi_agent_runtime_core_matrix_load'

      Assignment = Struct.new(:slot_index, :registration, :tasks, keyword_init: true) do
        # rubocop:disable Rails/Delegate
        def slot_label
          registration.slot_label
        end
        # rubocop:enable Rails/Delegate
      end

      class << self
        def call(...)
          new(...).call
        end
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
        failures = @registration_matrix.runtime_registrations.filter_map do |registration|
          next if registration.ready?

          "#{registration.slot_label} failed to boot: #{registration.boot_error || 'unknown boot failure'}"
        end

        return failures if sequential_turns_per_conversation?

        failures + [
          'unsupported max_in_flight_per_conversation=' \
            "#{@manifest.max_in_flight_per_conversation}; current workload driver only supports " \
            'sequential turns per conversation'
        ]
      end

      def sequential_turns_per_conversation?
        @manifest.respond_to?(:max_in_flight_per_conversation) &&
          @manifest.max_in_flight_per_conversation.to_i == 1
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
        @registration_matrix
          .runtime_registrations
          .cycle
          .take(@manifest.conversation_count)
          .map
          .with_index do |registration, index|
          Assignment.new(
            slot_index: index + 1,
            registration: registration,
            tasks: build_task_sequence(tasks, index)
          )
        end
      end

      def execute_assignments(assignments)
        results = Array.new(assignments.length)
        failures = []
        failure_mutex = Mutex.new

        threads = assignments.each_with_index.map do |assignment, index|
          Thread.new do
            results[index] = execute_assignment(assignment)
          rescue StandardError => e
            failure_mutex.synchronize { failures << e }
          ensure
            clear_active_database_connections!
          end
        end

        threads.each(&:join)
        raise failures.first if failures.any?

        results
      end

      def execute_assignment(assignment)
        conversation = create_conversation_for(assignment)
        shared_conversation = shared_conversation_for(conversation)

        assignment.tasks.each_with_index.map do |task, task_index|
          build_task_result(
            assignment: assignment,
            conversation: conversation,
            shared_conversation: shared_conversation,
            task: task,
            task_index: task_index
          )
        end
      end

      def shared_conversation_for(conversation)
        conversation.fetch(:conversation, conversation.fetch('conversation', conversation))
      end

      def build_task_sequence(tasks, assignment_index)
        Array.new(@manifest.turns_per_conversation) do |task_index|
          tasks.fetch((assignment_index + task_index) % tasks.length)
        end
      end

      def create_conversation_for(assignment)
        with_database_connection do
          @create_conversation.call(
            agent_definition_version: assignment.registration.agent_definition_version
          )
        end
      end

      def build_task_result(assignment:, conversation:, shared_conversation:, task:, task_index:)
        execution = with_database_connection do
          @execute_workload_item.call(
            conversation: shared_conversation,
            registration: assignment.registration,
            task: task,
            slot_index: assignment.slot_index
          )
        end

        {
          'slot_index' => assignment.slot_index,
          'slot_label' => assignment.slot_label,
          'registration' => assignment.registration,
          'conversation' => conversation,
          'task' => task,
          'task_sequence' => task_index + 1,
          'execution' => execution
        }
      end

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
        @registration_matrix.runtime_registrations.map(&:runtime_assignment_payload)
      end

      def serialize_workload_result(result)
        {
          'slot_index' => result.fetch('slot_index'),
          'slot_label' => result.fetch('slot_label'),
          'event_output_path' => result.fetch('registration').event_output_path,
          'task_sequence' => result.fetch('task_sequence'),
          'task' => result.fetch('task'),
          'execution' => result.fetch('execution')
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize
