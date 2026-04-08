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
          workload_kind: 'execution_assignment',
          deterministic: true
        },
        'target_8_fenix' => {
          runtime_count: 8,
          concurrent_conversations_per_runtime: 2,
          turns_per_conversation: 1,
          workload_kind: 'execution_assignment',
          deterministic: true
        },
        'stress' => {
          runtime_count: 8,
          concurrent_conversations_per_runtime: 4,
          turns_per_conversation: 3,
          workload_kind: 'program_exchange_mock',
          deterministic: true
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
                  :workload_kind

      def initialize(name:, definition:)
        @name = name
        @runtime_count = definition.fetch(:runtime_count)
        @concurrent_conversations_per_runtime = definition.fetch(:concurrent_conversations_per_runtime)
        @turns_per_conversation = definition.fetch(:turns_per_conversation)
        @workload_kind = definition.fetch(:workload_kind)
        @deterministic = definition.fetch(:deterministic)
      end

      def deterministic?
        @deterministic
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
