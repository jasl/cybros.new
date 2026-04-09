# frozen_string_literal: true

module Acceptance
  module Perf
    # Encapsulates a named load-harness profile and its derived sizing hints.
    class Profile
      DEFINITIONS = {
        'smoke' => {
          runtime_count: 2,
          concurrent_conversations_per_runtime: 2,
          turns_per_conversation: 1,
          max_in_flight_per_conversation: 1,
          workload_kind: 'execution_assignment',
          deterministic: true,
          gate_kind: 'correctness'
        },
        'target_8_fenix' => {
          runtime_count: 8,
          concurrent_conversations_per_runtime: 2,
          turns_per_conversation: 1,
          max_in_flight_per_conversation: 1,
          workload_kind: 'execution_assignment',
          deterministic: true
        },
        'stress' => {
          runtime_count: 8,
          concurrent_conversations_per_runtime: 4,
          turns_per_conversation: 3,
          max_in_flight_per_conversation: 1,
          workload_kind: 'program_exchange_mock',
          deterministic: true,
          gate_kind: 'pressure',
          required_metric_sample_paths: %w[
            mailbox_lease_latency.count
            mailbox_exchange_wait.count
            queue_pressure.total_sample_count
            database_checkout_pressure.checkout_wait.count
          ],
          max_database_checkout_timeouts: 0
        }
      }.freeze

      class << self
        def names
          DEFINITIONS.keys
        end

        def fetch(name)
          definition = DEFINITIONS.fetch(name.to_s) do
            raise KeyError, "unknown perf profile: #{name}"
          end

          new(name: name.to_s, definition: definition)
        end
      end

      attr_reader :name,
                  :runtime_count,
                  :concurrent_conversations_per_runtime,
                  :turns_per_conversation,
                  :max_in_flight_per_conversation,
                  :workload_kind

      def initialize(name:, definition:)
        @name = name
        @runtime_count = definition.fetch(:runtime_count)
        @concurrent_conversations_per_runtime = definition.fetch(:concurrent_conversations_per_runtime)
        @turns_per_conversation = definition.fetch(:turns_per_conversation)
        @max_in_flight_per_conversation = definition.fetch(:max_in_flight_per_conversation)
        @workload_kind = definition.fetch(:workload_kind)
        @deterministic = definition.fetch(:deterministic)
        @gate_kind = definition[:gate_kind]
        @required_metric_sample_paths = Array(definition[:required_metric_sample_paths]).freeze
        @max_database_checkout_timeouts = definition[:max_database_checkout_timeouts]
      end

      def deterministic?
        @deterministic
      end

      def expected_completed_workload_items
        conversation_count * turns_per_conversation
      end

      def gate_contract
        return nil if @gate_kind.to_s.empty?

        {
          "kind" => @gate_kind,
          "required_completed_workload_items" => expected_completed_workload_items,
          "required_metric_sample_paths" => @required_metric_sample_paths,
          "max_database_checkout_timeouts" => @max_database_checkout_timeouts,
        }.compact
      end

      def conversation_count
        runtime_count * concurrent_conversations_per_runtime
      end

      def recommended_runner_db_pool
        [conversation_count + runtime_count, 16].max
      end
    end
  end
end
