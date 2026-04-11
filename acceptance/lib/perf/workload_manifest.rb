# frozen_string_literal: true

module Acceptance
  module Perf
    class WorkloadManifest
      EXECUTION_ASSIGNMENT_REQUEST_CORPUS = [
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
      PROGRAM_EXCHANGE_MOCK_REQUEST_CORPUS = [
        {
          "content" => "3",
          "selector_source" => "manual",
          "selector" => "role:mock",
        },
        {
          "content" => "3",
          "selector_source" => "manual",
          "selector" => "role:mock",
        },
        {
          "content" => "3",
          "selector_source" => "manual",
          "selector" => "role:mock",
        },
        {
          "content" => "3",
          "selector_source" => "manual",
          "selector" => "role:mock",
        },
      ].freeze

      class << self
        def for_profile(profile)
          new(
            profile_name: profile.name,
            agent_count: profile.agent_count,
            execution_runtime_count: profile.execution_runtime_count,
            conversation_count: profile.conversation_count,
            turns_per_conversation: profile.turns_per_conversation,
            max_in_flight_per_conversation: profile.max_in_flight_per_conversation,
            workload_kind: profile.workload_kind,
            deterministic: profile.deterministic?,
            request_corpus: deep_freeze(
              marshal_copy(request_corpus_for(profile.workload_kind)).map do |entry|
                entry.merge("workload_kind" => profile.workload_kind)
              end
            )
          )
        end

        private

        def marshal_copy(value)
          Marshal.load(Marshal.dump(value))
        end

        def request_corpus_for(workload_kind)
          case workload_kind
          when "execution_assignment"
            EXECUTION_ASSIGNMENT_REQUEST_CORPUS
          when "agent_request_exchange_mock"
            PROGRAM_EXCHANGE_MOCK_REQUEST_CORPUS
          else
            raise ArgumentError, "unsupported workload kind: #{workload_kind}"
          end
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

      attr_reader :conversation_count,
                  :agent_count,
                  :execution_runtime_count,
                  :turns_per_conversation,
                  :max_in_flight_per_conversation,
                  :profile_name,
                  :request_corpus,
                  :workload_kind

      def initialize(profile_name:, agent_count:, execution_runtime_count:, conversation_count:, turns_per_conversation:, max_in_flight_per_conversation:, workload_kind:, deterministic:, request_corpus:)
        @profile_name = profile_name
        @agent_count = agent_count
        @execution_runtime_count = execution_runtime_count
        @conversation_count = conversation_count
        @turns_per_conversation = turns_per_conversation
        @max_in_flight_per_conversation = max_in_flight_per_conversation
        @workload_kind = workload_kind
        @deterministic = deterministic
        @request_corpus = request_corpus
      end

      def deterministic?
        @deterministic
      end

      def artifact_payload
        {
          "profile_name" => profile_name,
          "agent_count" => agent_count,
          "execution_runtime_count" => execution_runtime_count,
          "conversation_count" => conversation_count,
          "turns_per_conversation" => turns_per_conversation,
          "max_in_flight_per_conversation" => max_in_flight_per_conversation,
          "workload_kind" => workload_kind,
          "request_corpus" => request_corpus,
        }
      end
    end
  end
end
