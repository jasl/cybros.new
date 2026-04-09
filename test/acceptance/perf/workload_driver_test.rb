# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Lint/AmbiguousBlockAssociation, Layout/LineLength, Lint/RedundantRequireStatement
require 'minitest/autorun'
require 'pathname'

require_relative '../../../acceptance/lib/perf/runtime_registration_matrix'
require_relative '../../../acceptance/lib/perf/workload_driver'

module Acceptance
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
        :agent_program_version,
        :machine_credential,
        :executor_machine_credential,
        :deployment,
        keyword_init: true
      )

      def test_runtime_registration_matrix_builds_one_registration_per_runtime_slot
        topology = build_topology
        created_programs = []
        runtime_registrations = []

        matrix = RuntimeRegistrationMatrix.call(
          installation: :installation,
          actor: :actor,
          topology: topology,
          create_external_agent_program: lambda do |installation:, actor:, key:, display_name:|
            created_programs << { installation:, actor:, key:, display_name: }
            { agent_program: "program-#{key}", enrollment_token: "enroll-#{key}" }
          end,
          register_external_runtime: lambda do |enrollment_token:, runtime_base_url:, executor_fingerprint:, fingerprint:|
            runtime_registrations << { enrollment_token:, runtime_base_url:, executor_fingerprint:, fingerprint: }
            RuntimeRegistrationDouble.new(
              agent_program_version: "deployment-#{fingerprint}",
              machine_credential: "machine-#{fingerprint}",
              executor_machine_credential: "executor-#{fingerprint}",
              deployment: "deployment-#{fingerprint}"
            )
          end
        )

        assert_equal 2, matrix.runtime_count
        assert_equal topology.artifact_root.join('evidence', 'core-matrix-events.ndjson').to_s, matrix.core_matrix_events_path
        assert_equal %w[fenix-01 fenix-02], matrix.runtime_registrations.map(&:slot_label)
        assert_equal topology.runtime_slots.map { |slot| slot.event_output_path.to_s }, matrix.runtime_registrations.map(&:event_output_path)
        assert_equal topology.runtime_slots.map { |slot| runtime_task_env_for(slot) }, matrix.runtime_registrations.map(&:runtime_task_env)
        assert_equal %w[machine-fenix-01 machine-fenix-02], matrix.runtime_registrations.map { |registration| registration.runtime_registration.machine_credential }
        assert_equal 2, created_programs.length
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
          create_conversation: lambda do |agent_program_version:|
            conversation_id = "conversation-#{conversation_calls.length + 1}"
            conversation_calls << { conversation_id:, agent_program_version: }
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
        assert_equal %w[fenix-01 fenix-02 fenix-01 fenix-02], execution_calls.map { |entry| entry.fetch(:slot_label) }
        assert_equal registration_matrix.runtime_registrations.map(&:event_output_path), report.fetch('runtime_assignments').map { |entry| entry.fetch('event_output_path') }
        assert_equal(
          %w[deployment-fenix-01 deployment-fenix-02 deployment-fenix-01 deployment-fenix-02],
          conversation_calls.map { |entry| entry.fetch(:agent_program_version) }
        )
      end

      def test_workload_driver_reports_structural_failure_when_runtime_does_not_boot
        broken_matrix = registration_matrix.with_boot_state(
          slot_label: 'fenix-02',
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
        assert_includes report.fetch('structural_failures').first, 'fenix-02'
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
          create_conversation: lambda do |agent_program_version:|
            { conversation: "conversation-for-#{agent_program_version}" }
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
          runtime_count: 2,
          core_matrix_events_path: '/artifacts/core-matrix-events.ndjson',
          runtime_registrations: [
            build_registration('fenix-01', 'deployment-fenix-01', 'machine-01', 'executor-01', '/artifacts/fenix-01-events.ndjson'),
            build_registration('fenix-02', 'deployment-fenix-02', 'machine-02', 'executor-02', '/artifacts/fenix-02-events.ndjson')
          ]
        )
      end

      def build_registration(slot_label, agent_program_version, machine_credential, executor_machine_credential, event_output_path)
        RuntimeRegistrationMatrix::Registration.new(
          slot_label: slot_label,
          runtime_base_url: "http://127.0.0.1:#{slot_label.end_with?('01') ? '3101' : '3102'}",
          event_output_path: event_output_path,
          runtime_registration: RuntimeRegistrationDouble.new(
            agent_program_version: agent_program_version,
            machine_credential: machine_credential,
            executor_machine_credential: executor_machine_credential,
            deployment: agent_program_version
          ),
          runtime_task_env: {
            'FENIX_HOME_ROOT' => "/artifacts/#{slot_label}-home",
            'CYBROS_PERF_EVENTS_PATH' => event_output_path,
            'CYBROS_PERF_INSTANCE_LABEL' => slot_label
          },
          agent_program: "program-#{slot_label}",
          agent_program_version: agent_program_version,
          deployment: agent_program_version,
          machine_credential: machine_credential,
          executor_machine_credential: executor_machine_credential
        )
      end

      def build_topology
        TopologyDouble.new(
          artifact_root: Pathname('/tmp/load-artifacts'),
          runtime_slots: [
            Slot.new(
              label: 'fenix-01',
              runtime_base_url: 'http://127.0.0.1:3101',
              event_output_path: Pathname('/tmp/load-artifacts/evidence/fenix-01-events.ndjson'),
              home_root: Pathname('/tmp/load-artifacts/fenix-01-home')
            ),
            Slot.new(
              label: 'fenix-02',
              runtime_base_url: 'http://127.0.0.1:3102',
              event_output_path: Pathname('/tmp/load-artifacts/evidence/fenix-02-events.ndjson'),
              home_root: Pathname('/tmp/load-artifacts/fenix-02-home')
            )
          ]
        )
      end

      def runtime_task_env_for(slot)
        {
          'FENIX_HOME_ROOT' => slot.home_root.to_s,
          'CYBROS_PERF_EVENTS_PATH' => slot.event_output_path.to_s,
          'CYBROS_PERF_INSTANCE_LABEL' => slot.label
        }
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Lint/AmbiguousBlockAssociation, Layout/LineLength, Lint/RedundantRequireStatement
