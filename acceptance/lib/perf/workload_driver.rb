# frozen_string_literal: true

module Acceptance
  module Perf
    class WorkloadDriver
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

        assignments = build_assignments
        results = execute_assignments(assignments)

        {
          "benchmark_mode" => "multi_fenix_core_matrix_load",
          "outcome" => { "classification" => "descriptive_baseline" },
          "structural_failures" => [],
          "completed_workload_items" => results.count,
          "runtime_assignments" => serialize_runtime_assignments,
          "workload_results" => results.map { |result| serialize_workload_result(result) },
          "bottleneck_hints" => [],
        }
      end

      private

      def structural_failures
        @registration_matrix.fetch("runtime_registrations").filter_map do |registration|
          next if registration.fetch("boot_status", "ready") == "ready"

          "#{registration.fetch("slot_label")} failed to boot: #{registration.fetch("boot_error", "unknown boot failure")}"
        end
      end

      def structural_failure_report(failures)
        {
          "benchmark_mode" => "multi_fenix_core_matrix_load",
          "outcome" => { "classification" => "structural_failure" },
          "structural_failures" => failures,
          "completed_workload_items" => 0,
          "runtime_assignments" => serialize_runtime_assignments,
          "workload_results" => [],
          "bottleneck_hints" => [],
        }
      end

      def build_assignments
        tasks = Array(@manifest.request_corpus)
        runtime_registrations = @registration_matrix.fetch("runtime_registrations")

        Array.new(@manifest.conversation_count) do |index|
          registration = runtime_registrations.fetch(index % runtime_registrations.length)
          task = tasks.fetch(index % tasks.length)

          {
            "slot_index" => index + 1,
            "slot_label" => registration.fetch("slot_label"),
            "task" => task,
            "registration" => registration,
          }
        end
      end

      def execute_assignments(assignments)
        results = Array.new(assignments.length)
        failures = []
        failure_mutex = Mutex.new

        threads = assignments.each_with_index.map do |assignment, index|
          Thread.new do
            result = with_database_connection { execute_assignment(assignment) }
            results[index] = result
          rescue StandardError => error
            failure_mutex.synchronize do
              failures << error
            end
          end
        end

        threads.each(&:join)
        raise failures.first if failures.any?

        results
      end

      def execute_assignment(assignment)
        conversation = @create_conversation.call(
          agent_program_version: assignment.fetch("registration").fetch("agent_program_version")
        )
        execution = @execute_workload_item.call(
          conversation: conversation.fetch(:conversation, conversation.fetch("conversation", conversation)),
          registration: assignment.fetch("registration"),
          task: assignment.fetch("task"),
          slot_index: assignment.fetch("slot_index")
        )

        assignment.merge("conversation" => conversation, "execution" => execution)
      end

      def with_database_connection
        return yield unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection_pool.with_connection { yield }
      end

      def serialize_runtime_assignments
        @registration_matrix.fetch("runtime_registrations").map do |registration|
          registration.slice("slot_label", "runtime_base_url", "event_output_path", "boot_status")
        end
      end

      def serialize_workload_result(result)
        {
          "slot_index" => result.fetch("slot_index"),
          "slot_label" => result.fetch("slot_label"),
          "event_output_path" => result.fetch("registration").fetch("event_output_path"),
          "task" => result.fetch("task"),
          "execution" => result.fetch("execution"),
        }
      end
    end
  end
end
