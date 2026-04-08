# frozen_string_literal: true

module Acceptance
  module Perf
    class Profile
      DEFINITIONS = {
        "smoke" => {
          runtime_count: 2,
          concurrent_conversations_per_runtime: 2,
          max_in_flight_per_conversation: 1,
          deterministic: true,
        },
        "target_8_fenix" => {
          runtime_count: 8,
          concurrent_conversations_per_runtime: 2,
          max_in_flight_per_conversation: 1,
          deterministic: true,
        },
        "stress" => {
          runtime_count: 8,
          concurrent_conversations_per_runtime: 4,
          max_in_flight_per_conversation: 1,
          deterministic: true,
        },
      }.freeze

      class << self
        def names
          DEFINITIONS.keys
        end

        def fetch(name)
          definition = DEFINITIONS.fetch(name.to_s) do
            raise KeyError, "unknown perf profile: #{name}"
          end

          new(name: name.to_s, **definition)
        end
      end

      attr_reader :name,
        :runtime_count,
        :concurrent_conversations_per_runtime,
        :max_in_flight_per_conversation

      def initialize(name:, runtime_count:, concurrent_conversations_per_runtime:, max_in_flight_per_conversation:, deterministic:)
        @name = name
        @runtime_count = runtime_count
        @concurrent_conversations_per_runtime = concurrent_conversations_per_runtime
        @max_in_flight_per_conversation = max_in_flight_per_conversation
        @deterministic = deterministic
      end

      def deterministic?
        @deterministic
      end

      def conversation_count
        runtime_count * concurrent_conversations_per_runtime
      end
    end
  end
end
