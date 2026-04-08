# frozen_string_literal: true

module Acceptance
  module Perf
    class WorkloadManifest
      REQUEST_CORPUS = [
        {
          "content" => "External Fenix deterministic tool turn",
          "mode" => "deterministic_tool",
          "extra_payload" => { "expression" => "7 + 5" },
        },
        {
          "content" => "External Fenix deterministic tool turn",
          "mode" => "deterministic_tool",
          "extra_payload" => { "expression" => "9 * 4" },
        },
        {
          "content" => "External Fenix deterministic tool turn",
          "mode" => "deterministic_tool",
          "extra_payload" => { "expression" => "144 / 12" },
        },
        {
          "content" => "External Fenix deterministic tool turn",
          "mode" => "deterministic_tool",
          "extra_payload" => { "expression" => "11 - 3" },
        },
      ].freeze

      class << self
        def for_profile(profile)
          new(
            profile_name: profile.name,
            conversation_count: profile.conversation_count,
            max_in_flight_per_conversation: profile.max_in_flight_per_conversation,
            deterministic: profile.deterministic?,
            request_corpus: deep_freeze(marshal_copy(REQUEST_CORPUS))
          )
        end

        private

        def marshal_copy(value)
          Marshal.load(Marshal.dump(value))
        end

        def deep_freeze(value)
          case value
          when Array
            value.each { |entry| deep_freeze(entry) }
          when Hash
            value.each_value { |entry| deep_freeze(entry) }
          end

          value.freeze
        end
      end

      attr_reader :conversation_count, :max_in_flight_per_conversation, :profile_name, :request_corpus

      def initialize(profile_name:, conversation_count:, max_in_flight_per_conversation:, deterministic:, request_corpus:)
        @profile_name = profile_name
        @conversation_count = conversation_count
        @max_in_flight_per_conversation = max_in_flight_per_conversation
        @deterministic = deterministic
        @request_corpus = request_corpus
      end

      def deterministic?
        @deterministic
      end
    end
  end
end
