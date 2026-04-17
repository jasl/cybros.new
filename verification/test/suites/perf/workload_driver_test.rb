# frozen_string_literal: true
require_relative "../../test_helper"

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Lint/AmbiguousBlockAssociation, Layout/LineLength, Lint/RedundantRequireStatement
require 'minitest/autorun'
require 'pathname'

require "verification/suites/perf/runtime_registration_matrix"
require "verification/suites/perf/workload_driver"

module Verification
  module Perf
    # Exercises the typed runtime registration matrix and workload driver orchestration.
    class WorkloadDriverTest < Minitest::Test
      Slot = Struct.new(:label, :runtime_base_url, :event_output_path, :home_root, keyword_init: true)
      TopologyDouble = Struct.new(:artifact_root, :runtime_slots, keyword_init: true) do
        def runtime_count
          runtime_slots.length
        end
      end
      ManifestDouble = Struct.new(
        :conversation_count,
        :request_corpus,
        :turns_per_conversation,
        :max_in_flight_per_conversation,
        keyword_init: true
      )
      RuntimeRegistrationDouble = Struct.new(
        :agent_definition_version,
        :agent_connection_credential,
        :execution_runtime_connection_credential,
        :execution_runtime,
        keyword_init: true
      )

      def test_runtime_registration_matrix_builds_one_registration_per_runtime_slot
        topology = build_topology
        created_agents = []
        agent_registrations = []
        runtime_onboardings = []
        runtime_registrations = []

        matrix = RuntimeRegistrationMatrix.call(
          installation: :installation,
          actor: :actor,
          topology: topology,
          agent_count: 2,
          agent_base_url: "http://127.0.0.1:3100",
          create_bring_your_own_agent: lambda do |installation:, actor:, key:, display_name:|
            created_agents << { installation:, actor:, key:, display_name: }
            {
              agent: "agent-#{key}",
              onboarding_session: "onboarding-session-#{key}",
              onboarding_token: "onboard-#{key}"
            }
          end,
          register_bring_your_own_agent: lambda do |onboarding_token:, agent_base_url:|
            agent_registrations << { onboarding_token:, agent_base_url: }
            {
              agent_definition_version: "agent-definition-version-#{onboarding_token.delete_prefix('onboard-')}",
              agent_connection_credential: "agent-credential-#{onboarding_token.delete_prefix('onboard-')}",
            }
          end,
          create_bring_your_own_execution_runtime: lambda do |installation:, actor:|
            runtime_onboardings << { installation:, actor: }
            {
              onboarding_token: "runtime-onboard-#{runtime_onboardings.length}"
            }
          end,
          register_bring_your_own_execution_runtime: lambda do |onboarding_token:, runtime_base_url:, execution_runtime_fingerprint:|
            runtime_registrations << { onboarding_token:, runtime_base_url:, execution_runtime_fingerprint: }
            {
              execution_runtime: "execution-runtime-#{execution_runtime_fingerprint}",
              execution_runtime_connection_credential: "execution-runtime-credential-#{execution_runtime_fingerprint}",
            }
          end
        )

        assert_equal 2, matrix.agent_count
        assert_equal 2, matrix.runtime_count
        assert_equal topology.artifact_root.join('evidence', 'core-matrix-events.ndjson').to_s, matrix.core_matrix_events_path
        assert_equal %w[nexus-01 nexus-02], matrix.runtime_registrations.map(&:slot_label)
        assert_equal %w[fenix-01 fenix-02], matrix.runtime_registrations.map(&:agent_label)
        assert_equal topology.runtime_slots.map { |slot| slot.event_output_path.to_s }, matrix.runtime_registrations.map(&:event_output_path)
        assert_equal topology.runtime_slots.map { |slot| runtime_task_env_for(slot) }, matrix.runtime_registrations.map(&:runtime_task_env)
        assert_equal %w[agent-definition-version-multi-runtime-load-agent-01 agent-definition-version-multi-runtime-load-agent-02], matrix.runtime_registrations.map(&:agent_definition_version)
        assert_equal 2, created_agents.length
        assert_equal 2, agent_registrations.length
        assert_equal 2, runtime_onboardings.length
        assert_equal 2, runtime_registrations.length
      end

      def test_workload_driver_distributes_requests_round_robin
        manifest = ManifestDouble.new(
          conversation_count: 4,
          turns_per_conversation: 1,
          max_in_flight_per_conversation: 1,
          request_corpus: [
            execution_assignment_task('one', '1 + 1'),
            execution_assignment_task('two', '2 + 2')
          ]
        )
        conversation_calls = []
        execution_calls = []

        report = WorkloadDriver.call(
          manifest: manifest,
          registration_matrix: registration_matrix,
          create_conversation: lambda do |agent_definition_version:|
            conversation_id = "conversation-#{conversation_calls.length + 1}"
            conversation_calls << { conversation_id:, agent_definition_version: }
            { conversation: conversation_id }
          end,
          execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
            execution_calls << {
              conversation: conversation,
              slot_label: registration.slot_label,
              task: task,
              slot_index: slot_index
            }
            { 'status' => 'completed', 'conversation_id' => conversation }
          end
        )

        assert_equal 'descriptive_baseline', report.dig('outcome', 'classification')
        assert_equal 4, report.fetch('completed_workload_items')
        assert_equal %w[nexus-01 nexus-02 nexus-01 nexus-02], execution_calls.map { |entry| entry.fetch(:slot_label) }
        assert_equal registration_matrix.runtime_registrations.map(&:event_output_path), report.fetch('runtime_assignments').map { |entry| entry.fetch('event_output_path') }
        assert_equal(
          %w[agent-definition-version-fenix-01 agent-definition-version-fenix-02 agent-definition-version-fenix-01 agent-definition-version-fenix-02],
          conversation_calls.map { |entry| entry.fetch(:agent_definition_version) }
        )
      end

      def test_workload_driver_reports_structural_failure_when_runtime_does_not_boot
        broken_matrix = registration_matrix.with_boot_state(
          slot_label: 'nexus-02',
          status: 'failed',
          error: 'worker never became ready'
        )
        create_calls = []
        execution_calls = []

        report = WorkloadDriver.call(
          manifest: ManifestDouble.new(
            conversation_count: 2,
            turns_per_conversation: 1,
            max_in_flight_per_conversation: 1,
            request_corpus: [execution_assignment_task('one')]
          ),
          registration_matrix: broken_matrix,
          create_conversation: lambda do |**kwargs|
            create_calls << kwargs
            raise 'should not create conversations when boot failed'
          end,
          execute_workload_item: lambda do |**kwargs|
            execution_calls << kwargs
            raise 'should not execute workload when boot failed'
          end
        )

        assert_equal 'structural_failure', report.dig('outcome', 'classification')
        assert_includes report.fetch('structural_failures').first, 'nexus-02'
        assert_empty create_calls
        assert_empty execution_calls
      end

      def test_workload_driver_executes_workload_items_concurrently
        manifest = ManifestDouble.new(
          conversation_count: 4,
          turns_per_conversation: 1,
          max_in_flight_per_conversation: 1,
          request_corpus: [execution_assignment_task('one', '1 + 1')]
        )
        mutex = Mutex.new
        running = 0
        max_running = 0

        report = WorkloadDriver.call(
          manifest: manifest,
          registration_matrix: registration_matrix,
          create_conversation: lambda do |agent_definition_version:|
            { conversation: "conversation-for-#{agent_definition_version}" }
          end,
          execute_workload_item: lambda do |conversation:, registration:, task:, slot_index:|
            _unused_task = task
            mutex.synchronize do
              running += 1
              max_running = [max_running, running].max
            end
            sleep(0.05)
            {
              'status' => 'completed',
              'conversation_id' => conversation,
              'slot_label' => registration.slot_label,
              'slot_index' => slot_index
            }
          ensure
            mutex.synchronize do
              running -= 1
            end
          end
        )

        assert_equal 4, report.fetch('completed_workload_items')
        assert_operator max_running, :>, 1
      end

      def test_workload_driver_reports_structural_failure_for_unsupported_per_conversation_parallelism
        manifest = ManifestDouble.new(
          conversation_count: 2,
          turns_per_conversation: 1,
          max_in_flight_per_conversation: 2,
          request_corpus: [execution_assignment_task('one')]
        )

        report = WorkloadDriver.call(
          manifest: manifest,
          registration_matrix: registration_matrix,
          create_conversation: ->(**) { raise 'should not create conversations' },
          execute_workload_item: ->(**) { raise 'should not execute workload' }
        )

        assert_equal 'structural_failure', report.dig('outcome', 'classification')
        assert_includes report.fetch('structural_failures').first, 'max_in_flight_per_conversation'
      end

      private

      def execution_assignment_task(content, expression = nil)
        payload = { 'content' => content, 'mode' => 'deterministic_tool' }
        return payload unless expression

        payload.merge('extra_payload' => { 'expression' => expression })
      end

      def registration_matrix
        @registration_matrix ||= RuntimeRegistrationMatrix.new(
          agent_count: 2,
          runtime_count: 2,
          core_matrix_events_path: '/artifacts/core-matrix-events.ndjson',
          agent_registrations: [
            { label: "fenix-01", agent: "agent-fenix-01", agent_definition_version: "agent-definition-version-fenix-01" },
            { label: "fenix-02", agent: "agent-fenix-02", agent_definition_version: "agent-definition-version-fenix-02" }
          ],
          runtime_registrations: [
            build_registration('nexus-01', 'fenix-01', 'agent-definition-version-fenix-01', 'agent-credential-01', 'execution-runtime-credential-01', '/artifacts/nexus-01-events.ndjson'),
            build_registration('nexus-02', 'fenix-02', 'agent-definition-version-fenix-02', 'agent-credential-02', 'execution-runtime-credential-02', '/artifacts/nexus-02-events.ndjson')
          ]
        )
      end

      def build_registration(slot_label, agent_label, agent_definition_version, agent_connection_credential, execution_runtime_connection_credential, event_output_path)
        RuntimeRegistrationMatrix::Registration.new(
          slot_label: slot_label,
          agent_label: agent_label,
          runtime_base_url: "http://127.0.0.1:#{slot_label.end_with?('01') ? '3201' : '3202'}",
          event_output_path: event_output_path,
          runtime_registration: RuntimeRegistrationDouble.new(
            agent_definition_version: agent_definition_version,
            agent_connection_credential: agent_connection_credential,
            execution_runtime_connection_credential: execution_runtime_connection_credential,
            execution_runtime: "execution-runtime-#{slot_label}"
          ),
          runtime_task_env: {
            'NEXUS_HOME_ROOT' => "/artifacts/#{slot_label}-home",
            'NEXUS_STORAGE_ROOT' => "/artifacts/#{slot_label}-home/storage",
            'CYBROS_PERF_EVENTS_PATH' => event_output_path,
            'CYBROS_PERF_INSTANCE_LABEL' => slot_label
          },
          agent_definition_version: agent_definition_version,
          agent_connection_credential: agent_connection_credential,
          execution_runtime_connection_credential: execution_runtime_connection_credential,
          execution_runtime: "execution-runtime-#{slot_label}"
        )
      end

      def build_topology
        TopologyDouble.new(
          artifact_root: Pathname('/tmp/load-artifacts'),
          runtime_slots: [
            Slot.new(
              label: 'nexus-01',
              runtime_base_url: 'http://127.0.0.1:3201',
              event_output_path: Pathname('/tmp/load-artifacts/evidence/nexus-01-events.ndjson'),
              home_root: Pathname('/tmp/load-artifacts/nexus-01-home')
            ),
            Slot.new(
              label: 'nexus-02',
              runtime_base_url: 'http://127.0.0.1:3202',
              event_output_path: Pathname('/tmp/load-artifacts/evidence/nexus-02-events.ndjson'),
              home_root: Pathname('/tmp/load-artifacts/nexus-02-home')
            )
          ]
        )
      end

      def runtime_task_env_for(slot)
        {
          'NEXUS_HOME_ROOT' => slot.home_root.to_s,
          'NEXUS_STORAGE_ROOT' => slot.home_root.join('storage').to_s,
          'CYBROS_PERF_EVENTS_PATH' => slot.event_output_path.to_s,
          'CYBROS_PERF_INSTANCE_LABEL' => slot.label
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Lint/AmbiguousBlockAssociation, Layout/LineLength, Lint/RedundantRequireStatement
